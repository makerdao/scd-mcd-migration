pragma solidity ^0.5.12;

import "ds-token/token.sol";
import "ds-math/math.sol";

import { DssDeployTestBase } from "dss-deploy/DssDeploy.t.base.sol";
import { AuthGemJoin } from "dss-deploy/join.sol";
import { DssCdpManager } from "dss-cdp-manager/DssCdpManager.sol";
import { Spotter } from "dss/spot.sol";
import { DSProxy, DSProxyFactory } from "ds-proxy/proxy.sol";
import { WETH9_ } from "ds-weth/weth9.sol";

import {
    GemFab, VoxFab, DevVoxFab, TubFab, DevTubFab, TapFab,
    TopFab, DevTopFab, MomFab, DadFab, DevDadFab, DaiFab,
    DSValue, DSRoles, DevTub, SaiTap, SaiMom
} from "sai/sai.t.base.sol";

import { ScdMcdMigration } from "./ScdMcdMigration.sol";
import { MigrationProxyActions } from "./MigrationProxyActions.sol";

contract MockSaiPip {
    function peek() public pure returns (bytes32 val, bool zzz) {
        val = bytes32(uint(1 ether)); // 1 DAI = 1 SAI
        zzz = true;
    }
}

contract MockOtc is DSMath {
    function getPayAmount(address payGem, address buyGem, uint buyAmt) public pure returns (uint payAmt) {
        payGem;
        buyGem;
        payAmt = wmul(buyAmt, 300 ether); // Harcoded to simulate 300 payGem = 1 buyGem
    }

    function buyAllAmount(address buyGem, uint buyAmt, address payGem, uint maxPayAmt) public {
        uint payAmt = wmul(buyAmt, 300 ether);
        require(maxPayAmt >= payAmt, "");
        DSToken(payGem).transferFrom(msg.sender, address(this), payAmt);
        DSToken(buyGem).transfer(msg.sender, buyAmt);
    }
}

contract ScdMcdMigrationTest is DssDeployTestBase, DSMath {
    DevTub              tub;
    DSToken             sai;
    DSToken             skr;
    ScdMcdMigration     migration;
    DssCdpManager       manager;
    AuthGemJoin         saiJoin;
    Spotter             saiPrice;
    DSProxy             proxy;
    address             migrationProxyActions;
    MockOtc             otc;
    bytes32             cup;
    bytes32             cup2;

    function setUp() public {
        super.setUp();

        // Deploy MCD
        deployKeepAuth();

        // Deploy SCD
        deploySai();

        // Deploy Fake OTC
        otc = new MockOtc();

        // Give 1 MKR to Fake OTC
        gov.transfer(address(otc), 1 ether);

        // Create CDP Manager
        manager = new DssCdpManager(address(vat));

        // Create SAI collateral
        saiJoin = new AuthGemJoin(address(vat), "SAI", address(sai));
        dssDeploy.deployCollateral("SAI", address(saiJoin), address(new MockSaiPip()));

        // The highest we set the spot value, the most amount we can take from the CDP during the migrate function (as the process needs to take out collateral before paying the debt)
        // However the highest we set the spot value, the lowest can the maximum ink of the CDP be (due to uint256 overflow in frob: tab <= mul(urn.ink, ilk.spot))
        // We defined to use: "10 ** 50" which allows to have up to 1,157,920,892 SAI locked
        // Regarding how much it can be used in migrate function using "10 ** 50", here the analysis:
        // tab <= mul(urn.ink, ilk.spot)
        // 100,000 * 10 ** 45 (100K SAI locked) <= 1 * 10 ** 50 (passes, just 1 wei can't be used)
        // 1,000,000 * 10 ** 45 (1M SAI locked) <= 10 * 10 ** 50 (passes, just 10 wei can't be used)
        // 10,000,000 * 10 ** 45 (10M SAI locked) <= 100 * 10 ** 50 (passes, just 100 wei can't be used)
        this.file(address(spotter), "SAI", "mat", uint(10000));
        spotter.poke("SAI");
        (,, uint spot,,) = vat.ilks("SAI");
        assertEq(spot, 10 ** 50);

        // Total debt ceiling (100M)
        this.file(address(vat), bytes32("Line"), 100000000 * 10 ** 45);

        // Set ETH debt ceiling (100M)
        this.file(address(vat), bytes32("ETH"), bytes32("line"), 100000000 * 10 ** 45);

        // Set SAI debt ceiling (100M)
        this.file(address(vat), bytes32("SAI"), bytes32("line"), 100000000 * 10 ** 45);

        // Create Migration Contract
        migration = new ScdMcdMigration(
            address(tub),
            address(manager),
            address(saiJoin),
            address(ethJoin),
            address(daiJoin)
        );

        // Create Proxy Factory, proxy and migration proxy actions
        DSProxyFactory factory = new DSProxyFactory();
        proxy = DSProxy(factory.build());
        migrationProxyActions = address(new MigrationProxyActions());

        // Deposit, approve and join 20 ETH == 20 SKR
        weth.deposit.value(100001 ether)();
        weth.approve(address(tub), 100001 ether);
        tub.join(100001 ether);

        // Generate CDP for migrate
        cup = tub.open();
        tub.lock(cup, 100000 ether);
        tub.draw(cup, 9999999.999999999999999900 ether); // 1 ETH = 300 DAI => 300.0....03 % collateralization
        tub.give(cup, address(proxy));

        // Generate some extra SAI in another CDP
        cup2 = tub.open();
        tub.lock(cup2, 1 ether);
        tub.draw(cup2, 100);

        // Give access to the special authed SAI collateral to Migration contract
        saiJoin.rely(address(migration));
    }

    function deploySai() public {
        GemFab gemFab = new GemFab();
        DevVoxFab voxFab = new DevVoxFab();
        DevTubFab tubFab = new DevTubFab();
        TapFab tapFab = new TapFab();
        DevTopFab topFab = new DevTopFab();
        MomFab momFab = new MomFab();
        DevDadFab dadFab = new DevDadFab();

        DaiFab daiFab = new DaiFab(
            gemFab,
            VoxFab(address(voxFab)),
            TubFab(address(tubFab)),
            tapFab,
            TopFab(address(topFab)),
            momFab,
            DadFab(address(dadFab))
        );

        daiFab.makeTokens();
        DSValue pep = new DSValue();
        daiFab.makeVoxTub(ERC20(address(weth)), gov, pipETH, pep, address(123));
        daiFab.makeTapTop();
        daiFab.configParams();
        daiFab.verifyParams();
        DSRoles authority = new DSRoles();
        authority.setRootUser(address(this), true);
        daiFab.configAuth(authority);

        sai = DSToken(daiFab.sai());
        skr = DSToken(daiFab.skr());
        tub = DevTub(address(daiFab.tub()));

        sai.approve(address(tub));
        skr.approve(address(tub));
        weth.approve(address(tub), uint(-1));
        gov.approve(address(tub));

        SaiTap tap = SaiTap(daiFab.tap());

        sai.approve(address(tap));
        skr.approve(address(tap));

        pep.poke(bytes32(uint(300 ether)));

        SaiMom mom = SaiMom(daiFab.mom());

        mom.setCap(100000000 ether); // 100M SAI
        mom.setAxe(10 ** 27); // 0% liquidation penalty
        mom.setMat(10 ** 27); // 100% liqudation ratio
        mom.setTax(10 ** 27); // 0% stability fee
        mom.setFee(1.000001 * 10 ** 27); // governance fee
        mom.setTubGap(1 ether);
        mom.setTapGap(1 ether);
    }

    function migrate(address, address, bytes32) external returns (uint cdp) {
        bytes memory response = proxy.execute(migrationProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function migratePayFeeWithGem(address, address, bytes32, address, address, uint) external returns (uint cdp) {
        bytes memory response = proxy.execute(migrationProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }
    function migratePayFeeWithDebt(address, address, bytes32, address, uint, uint) external returns (uint cdp) {
        bytes memory response = proxy.execute(migrationProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function swapSaiToDai(address, uint) external {
        proxy.execute(migrationProxyActions, msg.data);
    }

    function swapDaiToSai(address, uint) external {
        proxy.execute(migrationProxyActions, msg.data);
    }

    function _swapSaiToDai(uint amount) internal {
        sai.approve(address(migration), amount);
        migration.swapSaiToDai(amount);
    }

    function testSwapSaiToDai() public {
        assertEq(sai.balanceOf(address(this)), 10000000 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        _swapSaiToDai(10000000 ether);
        assertEq(sai.balanceOf(address(this)), 0 ether);
        assertEq(dai.balanceOf(address(this)), 10000000 ether);
        (uint ink, uint art) = vat.urns("SAI", address(migration));
        assertEq(ink, 10000000 ether);
        assertEq(art, 10000000 ether);
    }

    function testSwapSaiToDaiProxy() public {
        assertEq(sai.balanceOf(address(this)), 10000000 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        sai.approve(address(proxy), 10000000 ether);
        this.swapSaiToDai(address(migration), 10000000 ether);
        assertEq(sai.balanceOf(address(this)), 0 ether);
        assertEq(dai.balanceOf(address(this)), 10000000 ether);
        (uint ink, uint art) = vat.urns("SAI", address(migration));
        assertEq(ink, 10000000 ether);
        assertEq(art, 10000000 ether);
    }

    function testFailSwapSaiToDaiAuth() public {
        sai.approve(address(migration), 10000000 ether);
        saiJoin.deny(address(migration));
        migration.swapSaiToDai(10000000 ether);
    }

    function testSwapDaiToSai() public {
        _swapSaiToDai(10000000 ether);
        dai.approve(address(migration), 6000000 ether);
        migration.swapDaiToSai(6000000 ether);
        assertEq(sai.balanceOf(address(this)), 6000000 ether);
        assertEq(dai.balanceOf(address(this)), 4000000 ether);
        (uint ink, uint art) = vat.urns("SAI", address(migration));
        assertEq(ink, 4000000 ether);
        assertEq(art, 4000000 ether);
    }

    function testSwapDaiToSaiProxy() public {
        _swapSaiToDai(10000000 ether);
        dai.approve(address(proxy), 6000000 ether);
        this.swapDaiToSai(address(migration), 6000000 ether);
        assertEq(sai.balanceOf(address(this)), 6000000 ether);
        assertEq(dai.balanceOf(address(this)), 4000000 ether);
        (uint ink, uint art) = vat.urns("SAI", address(migration));
        assertEq(ink, 4000000 ether);
        assertEq(art, 4000000 ether);
    }

    function testMigrate() public {
        _swapSaiToDai(10000000 ether);
        // After testSwapSaiToDai() migration contract holds a MCD CDP of 10000000 SAI.
        // As liquidation ratio is 0.00...100%, 99.99..900 SAI max can be used
        (,uint ink, uint art,) = tub.cups(cup);
        assertEq(ink, 100000 ether);
        assertEq(art, 9999999.999999999999999900 ether);
        (ink, art) = vat.urns("SAI", address(migration));
        assertEq(ink, 10000000 ether);
        assertEq(art, 10000000 ether);
        hevm.warp(3);
        (bytes32 val,) = tub.pep().peek();
        gov.approve(address(proxy), wdiv(tub.rap(cup), uint(val)));
        uint cdp = this.migrate(
            address(migration),
            address(jug),
            cup
        );
        (, ink, art,) = tub.cups(cup);
        assertEq(ink, 0);
        assertEq(art, 0);
        (ink, art) = vat.urns("SAI", address(migration));
        assertEq(ink, 100); // Dust that can not be migrated
        assertEq(art, 100);
        address urn = manager.urns(cdp);
        (ink, art) = vat.urns("ETH", urn);
        assertEq(ink, 100000 ether);
        assertEq(art, 9999999.999999999999999900 ether + 1); // the extra wei added for avoiding rounding issues
    }

    function testMigratePayFeeWithGem() public {
        _swapSaiToDai(10000000 ether);
        (bytes32 val,) = tub.pep().peek();
        hevm.warp(3);
        sai.approve(address(proxy), 30000030000009999900);
        tub.draw(cup2, 30000030000009999900); // Necessary DAI to purchase MKR
        uint cdp = this.migratePayFeeWithGem(
            address(migration),
            address(jug),
            cup,
            address(otc),
            address(sai),
            otc.getPayAmount(address(sai), address(gov),  wdiv(tub.rap(cup), uint(val)))
        );
        (, uint ink, uint art,) = tub.cups(cup);
        assertEq(ink, 0);
        assertEq(art, 0);
        (ink, art) = vat.urns("SAI", address(migration));
        assertEq(ink, 100);
        assertEq(art, 100);
        address urn = manager.urns(cdp);
        (ink, art) = vat.urns("ETH", urn);
        assertEq(ink, 100000 ether);
        assertEq(art, 9999999.999999999999999900 ether + 1); // the extra wei added for avoiding rounding issues
    }

    function testFailMigratePayFeeWithGemExceedsMax() public {
        _swapSaiToDai(10000000 ether);
        (bytes32 val,) = tub.pep().peek();
        hevm.warp(3);
        sai.approve(address(proxy), 30000030000009999900);
        tub.draw(cup2, 30000030000009999900); // Necessary DAI to purchase MKR
        this.migratePayFeeWithGem(
            address(migration),
            address(jug),
            cup,
            address(otc),
            address(sai),
            otc.getPayAmount(address(sai), address(gov),  wdiv(tub.rap(cup), uint(val)) - 1)
        );
    }

    function testMigratePayFeeWithDebt() public {
        // Debt fee: 30000030000009999900 wei SAI
        // + 300 extra necessary wei SAI as 1 extra MKR is being bought to avoid rounding issues
        // + 1 extra necessary wei SAI, as now we are exchanging a bit more than 100M SAI, then the remaining ammount needs to be over 100 (1 extra wei is enough)
        tub.draw(cup2, 30000030000009999900 + 300 + 1);
        _swapSaiToDai(10000000 ether + 30000030000009999900 + 300 + 1);
        (bytes32 val,) = tub.pep().peek();
        hevm.warp(3);
        // 300.0....03 % collateralization (prev migration)
        // Restriction: needs to be higher than 299% after generating new debt
        uint cdp = this.migratePayFeeWithDebt(
            address(migration),
            address(jug),
            cup,
            address(otc),
            otc.getPayAmount(address(sai), address(gov),  wdiv(tub.rap(cup), uint(val)) + 1),
            2.99 * 10 ** 27
        );
        (, uint ink, uint art,) = tub.cups(cup);
        assertEq(ink, 0);
        assertEq(art, 0);
        (ink, art) = vat.urns("SAI", address(migration));
        assertEq(ink, 101);
        assertEq(art, 101);
        address urn = manager.urns(cdp);
        (ink, art) = vat.urns("ETH", urn);
        assertEq(ink, 100000 ether);
        assertEq(art, 9999999.999999999999999900 ether + 30000030000009999900 + 300 + 1); // the extra wei added for avoiding rounding issues
    }

    function testFailMigratePayFeeWithDebtMaxPay() public {
        tub.draw(cup2, 30000030000009999900 + 300 + 1); // Necessary DAI to purchase MKR
        _swapSaiToDai(10000000 ether + 30000030000009999900 + 300 + 1);
        (bytes32 val,) = tub.pep().peek();
        hevm.warp(3);
        this.migratePayFeeWithDebt(
            address(migration),
            address(jug),
            cup,
            address(otc),
            otc.getPayAmount(address(sai), address(gov),  wdiv(tub.rap(cup), uint(val))),
            0 // Zero value to not interfere
        );
    }

    function testFailMigratePayFeeWithDebtMinRatio() public {
        tub.draw(cup2, 30000030000009999900 + 300 + 1); // Necessary DAI to purchase MKR
        _swapSaiToDai(10000000 ether + 30000030000009999900 + 300 + 1);
        hevm.warp(3);
        // 300.0....03 % collateralization (prev migration)
        // Restriction: needs to be higher than 300% after generating new debt (which fails)
        this.migratePayFeeWithDebt(
            address(migration),
            address(jug),
            cup,
            address(otc),
            999999999999 ether, // Big value to not interfere
            3 * 10 ** 27
        );
    }
}
