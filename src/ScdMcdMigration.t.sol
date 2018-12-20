pragma solidity >=0.5.0;

import "ds-token/token.sol";
import "ds-math/math.sol";

import {DssDeployTestBase} from "dss-deploy/DssDeploy.t.base.sol";
import {DssCdpManager} from "dss-cdp-manager/DssCdpManager.sol";
import {GemJoin} from "dss/join.sol";
import {GemMove} from "dss/move.sol";
import {Spotter} from "dss-deploy/poke.sol";
import {DSProxy, DSProxyFactory} from "ds-proxy/proxy.sol";

import "./ScdMcdMigration.sol";
import "./ProxyLib.sol";

contract WETH is DSToken("WETH") {
    function deposit() public payable {
        _balances[msg.sender] += msg.value;
    }

    function withdraw(uint wad) public {
        require(_balances[msg.sender] >= wad, "");
        _balances[msg.sender] -= wad;
        msg.sender.transfer(wad);
    }
}

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
    WETH        public  gem;
    DSToken     public  gov;
    MockPep     public  pep;
    address     cupLad;
    uint        cupArt;

    constructor(WETH gem_, DSToken skr_, DSToken gov_, DSToken sai_) public {
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

contract ScdMcdMigrationTest is DssDeployTestBase {
    DSToken             public  sai;
    DSToken             skr;
    WETH                gem;
    DSToken             gov;
    MockSaiTub          tub;
    ScdMcdMigration     migration;
    DssCdpManager       manager;
    GemJoin             saiJoin;
    GemMove             saiMove;
    Spotter             saiPrice;
    DSProxy             proxy;
    address             proxyLib;

    function setUp() public {
        super.setUp();

        gem = new WETH();
        gem.deposit.value(21 ether)();
        skr = new DSToken("SKR");
        skr.mint(20 ether);
        gov = new DSToken("MKR");
        gov.mint(20 ether);
        sai = new DSToken("SAI");
        sai.mint(100 ether);

        tub = new MockSaiTub(gem, skr, gov, sai);
        gem.transfer(address(tub), 21 ether);
        skr.transfer(address(tub), 20 ether);
        skr.setOwner(address(tub));
        sai.setOwner(address(tub));

        manager = new DssCdpManager();

        deploy();

        // Create SAI collateral
        saiJoin = new GemJoin(address(vat), "SAI", address(sai));
        saiMove = new GemMove(address(vat), "SAI");
        dssDeploy.deployCollateral("SAI", address(saiJoin), address(saiMove), address(new MockSaiPip()));
        (,,, saiPrice) = dssDeploy.ilks("SAI");
        this.file(address(saiPrice), uint(10 ** 25)); // 1% liquidation ratio (needed for CDP Migration)
        saiPrice.poke();
        this.file(address(pit), bytes32("SAI"), bytes32("line"), uint(10000 ether));

        migration = new ScdMcdMigration(
            address(tub),
            address(pit),
            address(manager),
            address(saiJoin),
            address(ethJoin),
            address(daiJoin)
        );

        DSProxyFactory factory = new DSProxyFactory();
        proxy = DSProxy(factory.build());
        proxyLib = address(new ProxyLib());

        tub.give(bytes32(uint(0x1)), address(proxy));

        sai.approve(address(migration));
        dai.approve(address(migration));
        gov.approve(address(proxy));
    }

    function migrate(address, bytes32) public returns (bytes12 cdp) {
        bytes memory response = proxy.execute(proxyLib, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function testSwapSaitoDai() public {
        assertEq(sai.balanceOf(address(this)), 100 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        migration.swapSaiToDai(100 ether);
        assertEq(sai.balanceOf(address(this)), 0 ether);
        assertEq(dai.balanceOf(address(this)), 100 ether);
        (uint ink, uint art) = vat.urns("SAI", bytes32(bytes20(address(migration))));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
    }

    function testSwapDaitoSai() public {
        testSwapSaitoDai();
        migration.swapDaiToSai(60 ether);
        assertEq(sai.balanceOf(address(this)), 60 ether);
        assertEq(dai.balanceOf(address(this)), 40 ether);
        (uint ink, uint art) = vat.urns("SAI", bytes32(bytes20(address(migration))));
        assertEq(ink, 40 ether);
        assertEq(art, 40 ether);
    }

    function testMigrateCDP() public {
        testSwapSaitoDai(); // Migration contract builds a MCD CDP of 100 SAI. As liquidation ratio is 1%, 99 SAI max can be used
        bytes32 cup = bytes32(uint(0x1));
        (,uint ink, uint art,) = tub.cups(cup);
        assertEq(ink, 20 ether); // 21 ETH = 20 SKR
        assertEq(art, 50 ether);
        bytes12 cdp = this.migrate(address(migration), cup);
        (, ink, art,) = tub.cups(cup);
        assertEq(ink, 0);
        assertEq(art, 0);
        bytes32 urn = manager.getUrn(cdp);
        (ink, art) = vat.urns("ETH", urn);
        assertEq(ink, 21 ether);
        assertEq(art, 50 ether + 1);
    }
}
