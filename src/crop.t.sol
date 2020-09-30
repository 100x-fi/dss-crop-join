pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./crop.sol";

contract Token {
    uint8 public decimals;
    mapping (address => uint) public balanceOf;
    constructor(uint8 dec, uint wad) public {
        decimals = dec;
        balanceOf[msg.sender] = wad;
    }
    function transfer(address usr, uint wad) public returns (bool) {
        require(balanceOf[msg.sender] >= wad, "transfer/insufficient");
        balanceOf[msg.sender] -= wad;
        balanceOf[usr] += wad;
        return true;
    }
    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad, "transferFrom/insufficient");
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        return true;
    }
    function mint(address dst, uint wad) public returns (uint) {
        balanceOf[dst] += wad;
    }
    function approve(address usr, uint wad) public returns (bool) {
    }
}

abstract contract cToken is Token {
    function underlying() public returns (address a) {}
    function balanceOfUnderlying(address owner) external returns (uint) {}
    function borrowBalanceStored(address account) external view returns (uint) {}
    function accrueInterest() external returns (uint) {}
}

contract Troll {
    Token comp;
    constructor(address comp_) public {
        comp = Token(comp_);
    }
    mapping (address => uint) public compAccrued;
    function reward(address usr, uint wad) public {
        compAccrued[usr] = wad;
    }
    function claimComp(address[] memory, address[] memory, bool, bool) public {
        comp.mint(msg.sender, compAccrued[msg.sender]);
        compAccrued[msg.sender] = 0;
    }
    function claimComp() public {
        comp.mint(msg.sender, compAccrued[msg.sender]);
        compAccrued[msg.sender] = 0;
    }
    function enterMarkets(address[] memory ctokens) public returns (uint[] memory) {
        comp; ctokens;
        uint[] memory err = new uint[](1);
        err[0] = 0;
        return err;
    }
    function compBorrowerIndex(address c, address b) public returns (uint) {}
    function mintAllowed(address ctoken, address minter, uint256 mintAmount) public returns (uint) {}
    function getBlockNumber() public view returns (uint) {
        return block.number;
    }
}

contract Usr {
    CropJoin j;
    constructor(CropJoin join_) public {
        j = join_;
    }
    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint(-1));
    }
    function join(uint wad) public {
        j.join(wad);
    }
    function exit(uint wad) public {
        j.exit(wad);
    }
    function reap() public {
        j.join(0);
    }
}


contract CropTestBase is DSTest {
    function assertTrue(bool b, bytes32 err) internal {
        if (!b) {
            emit log_named_bytes32("Fail: ", err);
            assertTrue(b);
        }
    }
    function assertEq(int a, int b, bytes32 err) internal {
        if (a != b) {
            emit log_named_bytes32("Fail: ", err);
            assertEq(a, b);
        }
    }
    function assertEq(uint a, uint b, bytes32 err) internal {
        if (a != b) {
            emit log_named_bytes32("Fail: ", err);
            assertEq(a, b);
        }
    }
    function assertGt(uint a, uint b, bytes32 err) internal {
        if (a <= b) {
            emit log_named_bytes32("Fail: ", err);
            assertGt(a, b);
        }
    }
    function assertGt(uint a, uint b) internal {
        if (a <= b) {
            emit log_bytes32("Error: a > b not satisfied");
            emit log_named_uint("         a", a);
            emit log_named_uint("         b", b);
            fail();
        }
    }
    function assertLt(uint a, uint b, bytes32 err) internal {
        if (a >= b) {
            emit log_named_bytes32("Fail: ", err);
            assertLt(a, b);
        }
    }
    function assertLt(uint a, uint b) internal {
        if (a >= b) {
            emit log_bytes32("Error: a < b not satisfied");
            emit log_named_uint("         a", a);
            emit log_named_uint("         b", b);
            fail();
        }
    }

    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    uint256 constant WAD  = 10 ** 18;
    function wdiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, WAD) / y;
    }

    Token    usdc;
    Token    cusdc;
    Token    comp;
    Troll    troll;
    MockVat  vat;
    CropJoin join;
    address  self;
    bytes32  ilk = "usdc-c";

    function init_user() internal returns (Usr a, Usr b) {
        a = new Usr(join);
        b = new Usr(join);

        usdc.transfer(address(a), 200 * 1e6);
        usdc.transfer(address(b), 200 * 1e6);

        a.approve(address(usdc), address(join));
        b.approve(address(usdc), address(join));
    }

    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function make_call(bytes memory data) internal returns (bool) {
        string memory try_sig = "try_call(address,bytes)";
        bytes memory can_call = abi.encodeWithSignature(try_sig, join, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_exit(uint val) public returns (bool) {
        return make_call(abi.encodeWithSignature
                           ("exit(uint256)", val)
                        );
    }
    function can_pour(uint val) public returns (bool) {
        return make_call(abi.encodeWithSignature
                           ("pour(uint256)", val)
                        );
    }
    function can_unwind(uint repay, uint n) public returns (bool) {
        return make_call(abi.encodeWithSignature
                           ("unwind(uint256,uint256)", repay, n)
                        );
    }
}

contract CropTest is CropTestBase {
    function setUp() public virtual {
        self  = address(this);
        usdc  = new Token(6, 1000 * 1e6);
        cusdc = new Token(8,  0);
        comp  = new Token(18, 0);
        troll = new Troll(address(comp));
        vat   = new MockVat();
        join  = new CropJoin( address(vat)
                            , ilk
                            , address(usdc)
                            , address(cusdc)
                            , address(comp)
                            , address(troll)
                            );
    }

    function reward(address usr, uint wad) internal virtual {
        troll.reward(usr, wad);
    }

    function test_reward() public {
        reward(self, 100 ether);
        assertEq(troll.compAccrued(self), 100 ether);
    }

    function test_simple_multi_user() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(join), 50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_multi_reap() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(join), 50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_join_exit() public {
        usdc.approve(address(join), uint(-1));

        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(join), 10 * 1e18);
        join.join(0); join.join(0);  // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over join");

        join.exit(200 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over exit");

        join.join(50 * 1e6);

        assertEq(comp.balanceOf(self), 10 * 1e18);
        reward(address(join), 10 * 1e18);
        join.join(10 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18);
    }
    function test_complex_scenario() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(join), 50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        reward(address(join), 50 * 1e18);
        a.join(20 * 1e6);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 60 * 1e18);
        assertEq(comp.balanceOf(address(b)), 40 * 1e18);

        reward(address(join), 30 * 1e18);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 80 * 1e18);
        assertEq(comp.balanceOf(address(b)), 50 * 1e18);

        b.exit(20 * 1e6);
    }

    // a user's balance can be altered with vat.flux, check that this
    // can only be disadvantageous
    function test_flux_transfer() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(join), 50 * 1e18);

        a.join(0); a.join(0); // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(join), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);
        b.join(0);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18, "if nonzero we have a problem");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        usdc.approve(address(join), uint(-1));

        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(join), 10 * 1e18);
        join.join(0); join.join(0);  // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        reward(address(join), 10 * 1e18);
        join.exit(50 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards increase with exit");

        reward(address(join), 10 * 1e18);
        join.flee(50 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards invariant over flee");
    }
}

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
}


// Here we run the basic CropTest tests against mainnet, overriding
// the Comptroller to accrue us COMP on demand
contract CompTest is CropTest {
    Hevm hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    function setUp() public override {
        self = address(this);
        vat  = new MockVat();

        usdc  =  Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        cusdc =  Token(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        comp  =  Token(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        troll =  Troll(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

        join = new CropJoin( address(vat)
                           , ilk
                           , address(usdc)
                           , address(cusdc)
                           , address(comp)
                           , address(troll)
                           );

        // give ourselves some usdc
        hevm.store(
            address(usdc),
            keccak256(abi.encode(address(this), uint256(9))),
            bytes32(uint(1000 * 1e6))
        );

        hevm.roll(block.number + 10);
    }

    function reward(address usr, uint wad) internal override {
        // override compAccrued in the comptroller
        hevm.store(
            address(troll),
            keccak256(abi.encode(usr, uint256(20))),
            bytes32(wad)
        );
    }

    function test_borrower_index() public {
        assertEq(troll.compBorrowerIndex(address(cusdc), address(join)), 0);
    }

    function test_setup() public {
        assertEq(usdc.balanceOf(self), 1000 * 1e6, "hack the usdc");
    }

    function test_block_number() public {
        assertEq(troll.getBlockNumber(), block.number);
    }

    function test_join() public {
        usdc.approve(address(join), uint(-1));
        join.join(100 * 1e6);
    }
}

// Here we run some tests against the real Compound on mainnet
contract RealCompTest is CropTestBase {
    Hevm hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    function setUp() public {
        self = address(this);
        vat  = new MockVat();

        usdc  =  Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        cusdc =  Token(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        comp  =  Token(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        troll =  Troll(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

        join = new CropJoin( address(vat)
                           , ilk
                           , address(usdc)
                           , address(cusdc)
                           , address(comp)
                           , address(troll)
                           );

        // give ourselves some usdc
        hevm.store(
            address(usdc),
            keccak256(abi.encode(address(this), uint256(9))),
            bytes32(uint(1000 * 1e6))
        );

        hevm.roll(block.number + 10);

        usdc.approve(address(join), uint(-1));
    }

    function get_cf() internal returns (uint256 cf) {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        cf = wdiv(cToken(address(cusdc)).borrowBalanceStored(address(join)),
                  cToken(address(cusdc)).balanceOfUnderlying(address(join)));
    }

    function test_underlying() public {
        assertEq(cToken(address(cusdc)).underlying(), address(usdc));
    }

    function reward(uint256 tic) internal {
        // accrue ~1 day of rewards
        hevm.warp(block.timestamp + tic);
        // unneeded?
        hevm.roll(block.number + tic / 15);
    }

    function test_reward_unwound() public {
        (Usr a, Usr b) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        join.wind(0, 0);

        reward(1 days);

        a.join(0);
        // ~ 0.012 COMP per year
        assertTrue(comp.balanceOf(address(a)) > 0.00003 ether);
        assertTrue(comp.balanceOf(address(a)) < 0.00004 ether);
    }

    function test_reward_wound() public {
        (Usr a, Usr b) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        join.wind(50 * 10**6, 0);

        reward(1 days);

        a.join(0);
        // ~ 0.035 COMP per year
        assertTrue(comp.balanceOf(address(a)) > 0.00009 ether);
        assertTrue(comp.balanceOf(address(a)) < 0.0001 ether);

        assertTrue(get_cf() < join.maxf());
        assertTrue(get_cf() < join.minf());
    }

    function test_reward_wound_fully() public {
        (Usr a, Usr b) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        join.wind(0, 4);

        reward(1 days);

        a.join(0);
        // ~ 0.11 COMP per year
        assertGt(comp.balanceOf(address(a)), 0.00029 ether);
        assertLt(comp.balanceOf(address(a)), 0.00032 ether);

        assertLt(get_cf(), join.maxf(), "cf < maxf");
        assertGt(get_cf(), join.minf(), "cf > minf");
    }

    function testFail_over_wind() public {
        (Usr a, Usr b) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        join.wind(0, 5);
    }

    function test_wind_unwind() public {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        (Usr a, Usr b) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        join.wind(0, 4);

        reward(1 days);

        assertLt(get_cf(), join.maxf(), "under target");
        assertGt(get_cf(), join.minf(), "over minimum");

        assertTrue(!can_unwind(0, 1), "unable to unwind if under target");
        reward(300 days);

        assertTrue(get_cf() > join.maxf(), "over target after interest");

        // unwind is used for deleveraging our position. Here we have
        // gone over the target due to accumulated interest, so we
        // unwind to bring us back under the target leverage.
        assertTrue( can_unwind(0, 1), "able to unwind if over target");
        assertTrue(!can_unwind(0, 2), "unable to unwind below minimum");
        join.unwind(0, 1);

        assertLt(get_cf(), join.maxf(), "under target post unwind");
        assertGt(get_cf(), join.minf(), "over minimum post unwind");
    }

    // wind / unwind make the underlying unavailable as it is deposited
    // into the ctoken. In order to exit we will have to free up some
    // underlying.
    function test_wound_pour_exit() public {
        join.join(100 * 1e6);

        assertEq(comp.balanceOf(self), 0 ether, "no initial rewards");

        join.wind(0, 4);
        reward(1 days);

        assertTrue(get_cf() < join.maxf(), "cf under target");
        assertTrue(get_cf() > join.minf(), "cf over minimum");

        log_named_uint("cfpre", get_cf());

        // we can't exit as there is no available usdc
        assertTrue(!can_exit(10 * 1e6), "cannot 10% exit initially");

        // however we can pour
        assertTrue( can_pour(16 * 1e6), "ok exit with 16% pour");
        assertTrue(!can_pour(17 * 1e6), "no exit with 17% pour");

        uint prev = usdc.balanceOf(address(this));
        join.pour(10 * 1e6);
        assertEq(usdc.balanceOf(address(this)) - prev, 10 * 1e6);
    }
}
