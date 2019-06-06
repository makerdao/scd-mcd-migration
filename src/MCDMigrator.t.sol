pragma solidity >=0.5.0;

import "ds-token/token.sol";
import "ds-math/math.sol";

import {DssDeployTestBase} from "dss-deploy/DssDeploy.t.base.sol";
import {DssCdpManager} from "dss-cdp-manager/DssCdpManager.sol";
import {GemJoin} from "dss/join.sol";
import {Spotter} from "dss-deploy/poke.sol";
import {DSProxy, DSProxyFactory} from "ds-proxy/proxy.sol";
import {WETH9_} from "ds-weth/weth9.sol";

import "./MCDMigrator.sol";
import "./ProxyLib.sol";

contract MockSaiPip {
    function peek() public pure returns (bytes32 val, bool zzz) {
        val = bytes32(uint(1 ether)); // 1 DAI = 1 SAI
        zzz = true;
    }
}

contract MockPep {
    function peek() public pure returns (bytes32 val, bool zzz) {
        val = bytes32(uint(300 ether)); // 300 SAI = 1 MKR
        zzz = true;
    }
}

contract MockSaiTub is DSMath {
    DSToken     public  sai;
    DSToken     public  skr;
    WETH9_      public  gem;
    DSToken     public  gov;
    MockPep     public  pep;
    address     cupLad;
    uint        cupArt;

    constructor(WETH9_ gem_, DSToken skr_, DSToken gov_, DSToken sai_) public {
        gem = gem_;
        skr = skr_;
        gov = gov_;
        sai = sai_;
        pep = new MockPep();
        cupLad = msg.sender;
        cupArt = 50 ether; // Random debt
    }

    function cups(bytes32) public view returns (address lad_, uint ink_, uint art_, uint) {
        lad_ = cupLad;
        ink_ = skr.balanceOf(address(this));
        art_ = cupArt;
    }

    function bid(uint wad) public view returns (uint) {
        return rmul(wad, per());
    }

    function lad(bytes32 cup) public view returns (address lad_) {
        (lad_,,,) = cups(cup);
    }

    function ink(bytes32 cup) public view returns (uint ink_) {
        (, ink_,,) = cups(cup);
    }

    function tab(bytes32 cup) public view returns (uint art_) {
        (,, art_,) = cups(cup);
    }

    function rap(bytes32) public pure returns (uint) {
        return uint(5 ether); // Random governance + stability fees accumulated
    }

    function per() public view returns (uint ray) {
        return skr.totalSupply() == 0 ? RAY : rdiv(gem.balanceOf(address(this)), skr.totalSupply());
    }

    function exit(uint wad) public {
        gem.transfer(msg.sender, rmul(wad, per()));
        skr.burn(msg.sender, wad);
    }

    function shut(bytes32 cup) public {
        require(cupLad == msg.sender, "");
        uint owe = rap(cup);
        sai.burn(msg.sender, tab(cup));
        (bytes32 val,) = pep.peek();
        gov.move(msg.sender, address(123), wdiv(owe, uint(val)));
        skr.push(msg.sender, ink(cup));
        cupLad = address(0);
        cupArt = 0;
    }

    function give(bytes32, address guy) public {
        require(cupLad == msg.sender, "");
        cupLad = guy;
    }
}

contract MCDMigratorTest is DssDeployTestBase {
    DSToken             sai;
    DSToken             skr;
    WETH9_              gem;
    DSToken             gov;
    MockSaiTub          tub;
    MCDMigrator         migrator;
    DssCdpManager       manager;
    GemJoin             saiJoin;
    Spotter             saiPrice;
    DSProxy             proxy;
    address             proxyLib;

    function setUp() public {
        super.setUp();

        deployKeepAuth();

        weth.deposit.value(21 ether)();
        skr = new DSToken("SKR");
        skr.mint(20 ether);
        gov = new DSToken("MKR");
        gov.mint(20 ether);
        sai = new DSToken("SAI");
        sai.mint(100 ether);

        tub = new MockSaiTub(weth, skr, gov, sai);
        weth.transfer(address(tub), 21 ether);
        skr.transfer(address(tub), 20 ether);
        skr.setOwner(address(tub));
        sai.setOwner(address(tub));

        manager = new DssCdpManager(address(vat));

        // Create SAI collateral
        saiJoin = new GemJoin(address(vat), "SAI", address(sai));
        dssDeploy.deployCollateral("SAI", address(saiJoin), address(new MockSaiPip()));
        this.file(address(vat), bytes32("SAI"), bytes32("spot"), uint(10 ** 27));
        this.file(address(vat), bytes32("SAI"), bytes32("line"), 10000 * 10 ** 45);

        migrator = new MCDMigrator(
            address(tub),
            address(vat),
            address(manager),
            address(saiJoin),
            address(ethJoin),
            address(daiJoin)
        );

        DSProxyFactory factory = new DSProxyFactory();
        proxy = DSProxy(factory.build());
        proxyLib = address(new ProxyLib());

        tub.give(bytes32(uint(0x1)), address(proxy));

        sai.approve(address(saiJoin), uint(-1));
        sai.approve(address(migrator), uint(-1));
        dai.approve(address(migrator), uint(-1));
        gov.approve(address(proxy), uint(-1));
    }

    function migrate(address, bytes32) public returns (uint cdp) {
        bytes memory response = proxy.execute(proxyLib, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function testSai2Dai() public {
        assertEq(sai.balanceOf(address(this)), 100 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        migrator.sai2dai(100 ether);
        assertEq(sai.balanceOf(address(this)), 0 ether);
        assertEq(dai.balanceOf(address(this)), 100 ether);
        (uint ink, uint art) = vat.urns("SAI", address(migrator));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
    }

    function testDai2Sai() public {
        testSai2Dai();
        migrator.dai2sai(60 ether);
        assertEq(sai.balanceOf(address(this)), 60 ether);
        assertEq(dai.balanceOf(address(this)), 40 ether);
        (uint ink, uint art) = vat.urns("SAI", address(migrator));
        assertEq(ink, 40 ether);
        assertEq(art, 40 ether);
    }

    function sendFunds() public {
        uint cdp = manager.open("ETH");
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);

        ethJoin.join(manager.urns(cdp), 1 ether);
        manager.frob(cdp, address(this), 1 ether, 50 ether);
        vat.hope(address(migrator));
        migrator.vatMoveIn(50 * 10 ** 45);
    }

    function testMoveFundsIn() public {
        assertEq(vat.dai(address(migrator)), 0);
        sendFunds();
    }

    function testMoveFundsOut() public {
        sendFunds();
        assertEq(vat.dai(address(migrator)), 50 * 10 ** 45);
        assertEq(vat.dai(address(this)), 0);
        migrator.vatMoveOut(20 * 10 ** 45);
        assertEq(vat.dai(address(migrator)), 30 * 10 ** 45);
        assertEq(vat.dai(address(this)), 20 * 10 ** 45);
        migrator.vatMoveOut(30 * 10 ** 45);
        assertEq(vat.dai(address(migrator)), 0);
        assertEq(vat.dai(address(this)), 50 * 10 ** 45);
    }

    function testMigrateCDP() public {
        testSai2Dai(); // migrator contract builds a MCD CDP of 100 DAI
        sendFunds();
        bytes32 cup = bytes32(uint(1));
        (,uint ink, uint art,) = tub.cups(cup);
        assertEq(ink, 20 ether); // 21 ETH = 20 SKR
        assertEq(art, 50 ether);
        uint cdp = this.migrate(address(migrator), cup);
        assertEq(vat.dai(address(migrator)), 50 * 10 ** 45);
        (, ink, art,) = tub.cups(cup);
        assertEq(ink, 0);
        assertEq(art, 0);
        address urn = manager.urns(cdp);
        (ink, art) = vat.urns("ETH", urn);
        assertEq(ink, 21 ether);
        assertEq(art, 50 ether + 1);
    }
}
