pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

interface ERC20 {
    function balanceOf(address owner) external view returns (uint);
    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function decimals() external returns (uint8);
}

interface CToken is ERC20 {
    function admin() external returns (address);
    function pendingAdmin() external returns (address);
    function comptroller() external returns (address);
    function interestRateModel() external returns (address);
    function initialExchangeRateMantissa() external returns (uint);
    function reserveFactorMantissa() external returns (uint);
    function accrualBlockNumber() external returns (uint);
    function borrowIndex() external returns (uint);
    function totalBorrows() external returns (uint);
    function totalReserves() external returns (uint);
    function totalSupply() external returns (uint);
    function accountTokens(address) external returns (uint);
    function transferAllowances(address,address) external returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function getCash() external view returns (uint);
    function accrueInterest() external returns (uint);
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);

    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, CToken cTokenCollateral) external returns (uint);
}

interface Comptroller {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function claimComp(address[] calldata holders, address[] calldata cTokens, bool borrowers, bool suppliers) external;
    function compAccrued(address) external returns (uint);
    function compBorrowerIndex(address,address) external returns (uint);
    function compSupplierIndex(address,address) external returns (uint);
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint);
    function getAccountLiquidity(address) external returns (uint,uint,uint);
}

struct Urn {
    uint256 ink;   // Locked Collateral  [wad]
    uint256 art;   // Normalised Debt    [wad]
}

interface VatLike {
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external;
    function  gem(bytes32 ilk, address usr) external returns (uint);
    function urns(bytes32 ilk, address usr) external returns (Urn memory);
}

// receives tokens and shares them among holders
contract CropJoin {
    VatLike     public vat;
    bytes32     public ilk;
    ERC20       public gem;
    uint256     public dec;

    CToken      public cgem;
    ERC20       public comp;
    Comptroller public comptroller;

    uint256     public share;  // crops per gem
    uint256     public total;  // total gems
    uint256     public stock;  // crop balance

    mapping (address => uint) public crops; // crops per user
    mapping (address => uint) public stake; // gems per user

    constructor(address vat_, bytes32 ilk_, address gem_,
                address cgem_, address comp_, address comptroller_) public
    {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = ERC20(gem_);
        dec = gem.decimals();
        require(dec <= 18);

        cgem = CToken(cgem_);
        comp = ERC20(comp_);
        comptroller = Comptroller(comptroller_);

        gem.approve(address(cgem), uint(-1));

        address[] memory ctokens = new address[](1);
        ctokens[0] = address(cgem);
        uint256[] memory errors = new uint[](1);
        errors = comptroller.enterMarkets(ctokens);
        require(errors[0] == 0);
    }

    function add(uint x, uint y) public pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) public pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    uint256 constant WAD  = 10 ** 18;
    function wmul(uint x, uint y) public pure returns (uint z) {
        z = mul(x, y) / WAD;
    }
    function wdiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, WAD) / y;
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }

    function nav() public returns (uint) {
        uint _nav = add(gem.balanceOf(address(this)),
                        sub(cgem.balanceOfUnderlying(address(this)),
                            cgem.borrowBalanceCurrent(address(this))));
        return mul(_nav, 10 ** (18 - dec));
    }
    function nps() public returns (uint) {
        if (total == 0) return WAD;
        else return wdiv(nav(), total);
    }

    function crop() internal virtual returns (uint) {
        address[] memory ctokens = new address[](1);
        address[] memory users   = new address[](1);
        ctokens[0] = address(cgem);
        users  [0] = address(this);

        comptroller.claimComp(users, ctokens, true, true);
        return sub(comp.balanceOf(address(this)), stock);
    }

    // decimals: underlying=dec cToken=8 comp=18 gem=18
    function join(uint256 val) public {
        uint wad = wdiv(mul(val, 10 ** (18 - dec)), nps());
        require(int(wad) >= 0);

        if (total > 0) share = add(share, wdiv(crop(), total));

        address usr = msg.sender;
        require(comp.transfer(msg.sender, sub(wmul(stake[usr], share), crops[usr])));
        stock = comp.balanceOf(address(this));
        if (wad > 0) {
            require(gem.transferFrom(usr, address(this), val));
            vat.slip(ilk, usr, int(wad));

            total = add(total, wad);
            stake[usr] = add(stake[usr], wad);
        }
        crops[usr] = wmul(stake[usr], share);
    }

    function exit(uint val) public {
        uint wad = wdiv(mul(val, 10 ** (18 - dec)), nps());
        require(int(wad) >= 0);

        if (total > 0) share = add(share, wdiv(crop(), total));

        address usr = msg.sender;
        require(comp.transfer(msg.sender, sub(wmul(stake[usr], share), crops[usr])));
        stock = comp.balanceOf(address(this));
        if (wad > 0) {
            require(gem.transfer(usr, val));
            vat.slip(ilk, usr, -int(wad));

            total = sub(total, wad);
            stake[usr] = sub(stake[usr], wad);
        }
        crops[usr] = wmul(stake[usr], share);
    }

    function flee() public {
        address usr = msg.sender;

        uint wad = vat.gem(ilk, usr);
        uint val = wmul(wmul(wad, nps()), 10 ** dec);

        require(gem.transfer(usr, val));
        vat.slip(ilk, usr, -int(wad));

        total = sub(total, wad);
        stake[usr] = sub(stake[usr], wad);
        crops[usr] = wmul(stake[usr], share);
    }

    function tack(address src, address dst, uint wad) public {
        // collect and pay out any pending rewards
        if (total > 0) share = add(share, wdiv(crop(), total));
        require(comp.transfer(src, sub(wmul(stake[src], share), crops[src])));
        require(comp.transfer(dst, sub(wmul(stake[dst], share), crops[dst])));
        stock = comp.balanceOf(address(this));

        stake[src] = sub(stake[src], wad);
        stake[dst] = add(stake[dst], wad);

        require(stake[src] >= add(vat.gem(ilk, src), vat.urns(ilk, src).ink));
        require(stake[dst] <= add(vat.gem(ilk, dst), vat.urns(ilk, dst).ink));

        crops[src] = wmul(stake[src], share);
        crops[dst] = wmul(stake[dst], share);
    }

    uint256 public cf   = 0.75   ether;  // usdc max collateral factor
    uint256 public maxf = 0.675  ether;  // maximum collateral factor  (90%)
    uint256 public minf = 0.6375 ether;  // minimum collateral factor  (85%)

    // borrow_: how much underlying to borrow (dec decimals)
    // loops_:  how many times to repeat a max borrow loop before the
    //          specified borrow/mint
    // loan_:  how much underlying to lend to the contract for this
    //         transaction
    function wind(uint borrow_, uint loops_, uint loan_) public {
        require(cgem.accrueInterest() == 0);
        if (loan_ > 0) {
            require(gem.transferFrom(msg.sender, address(this), loan_));
        }
        uint gems = gem.balanceOf(address(this));
        if (gems > 0) {
            require(cgem.mint(gems) == 0);
        }

        for (uint i=0; i < loops_; i++) {
            uint s = cgem.balanceOfUnderlying(address(this));
            uint b = cgem.borrowBalanceStored(address(this));
            uint x1 = sub(wmul(s, cf), b);
            uint x2 = wdiv(sub(wmul(sub(s, loan_), maxf), b),
                           sub(1e18, maxf));
            uint max_borrow = min(x1, x2);
            if (max_borrow > 0) {
                require(cgem.borrow(max_borrow) == 0);
                require(cgem.mint(max_borrow) == 0);
            }
        }
        if (borrow_ > 0) {
            require(cgem.borrow(borrow_) == 0);
            require(cgem.mint(borrow_) == 0);
        }
        if (loan_ > 0) {
            require(cgem.redeemUnderlying(loan_) == 0);
            require(gem.transfer(msg.sender, loan_));
        }

        uint u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        require(u < maxf);
    }
    // repay_: how much underlying to repay (dec decimals)
    // loops_: how many times to repeat a max repay loop before the
    //         specified redeem/repay
    // exit_:  how much underlying to remove following unwind
    // loan_:  how much underlying to lend to the contract for this
    //         transaction
    function unwind(uint repay_, uint loops_, uint exit_, uint loan_) public {
        require(cgem.accrueInterest() == 0);
        if (loan_ > 0) {
            require(gem.transferFrom(msg.sender, address(this), loan_));
        }
        require(cgem.mint(gem.balanceOf(address(this))) == 0);

        uint u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        for (uint i=0; i < loops_; i++) {
            uint s = cgem.balanceOfUnderlying(address(this));
            uint b = cgem.borrowBalanceStored(address(this));
            uint x1 = wdiv(sub(wmul(s, cf), b), cf);
            uint x2 = wdiv(sub(add(b, wmul(exit_, maxf)),
                               wmul(sub(s, loan_), maxf)),
                           sub(1e18, maxf));
            uint max_repay = min(x1, x2);
            if (max_repay > 0) {
                require(cgem.redeemUnderlying(max_repay) == 0);
                require(cgem.repayBorrow(max_repay) == 0);
            }
        }
        if (repay_ > 0) {
            require(cgem.redeemUnderlying(repay_) == 0);
            require(cgem.repayBorrow(repay_) == 0);
        }
        if (exit_ > 0 || loan_ > 0) {
            require(cgem.redeemUnderlying(add(exit_, loan_)) == 0);
        }
        if (loan_ > 0) {
            require(gem.transfer(msg.sender, loan_));
        }
        if (exit_ > 0) {
            exit(exit_);
        }

        uint u_ = wdiv(cgem.borrowBalanceStored(address(this)),
                       cgem.balanceOfUnderlying(address(this)));
        bool ramping = u  < minf && u_ > u && u_ < maxf;
        bool damping = u  > maxf && u_ < u && u_ > minf;
        bool tamping = u_ > minf && u_ < maxf;
        require(ramping || damping || tamping);
    }
}
