pragma solidity 0.5.11;

import "ds-token/token.sol";

import { DssDeployTestBase } from "dss-deploy/DssDeploy.t.base.sol";
import { AuthGemJoin } from "dss-deploy/join.sol";

import { SaiDaiMigration } from "./SaiDaiMigration.sol";

contract ScdMcdMigrationTest is DssDeployTestBase {
    DSToken             sai;
    SaiDaiMigration     migration;
    AuthGemJoin         saiJoin;

    function setUp() public {
        super.setUp();

        // Deploy MCD
        deployKeepAuth();

        // Create dummy SAI token
        sai = new DSToken("SAI");
        sai.mint(address(this), 10000000 ether);

        // Create SAI collateral
        saiJoin = new AuthGemJoin(address(vat), "SAI", address(sai));
        dssDeploy.deployCollateral("SAI", address(saiJoin), address(0));

        // The highest we set the spot value, the most amount we can take from the CDP during the migrate function (as the process needs to take out collateral before paying the debt)
        // However the highest we set the spot value, the lowest can the maximum ink of the CDP be (due to uint256 overflow in frob: tab <= mul(urn.ink, ilk.spot))
        // We defined to use: "10 ** 50" which allows to have up to 1,157,920,892 SAI locked
        // Regarding how much it can be used in migrate function using "10 ** 50", here the analysis:
        // tab <= mul(urn.ink, ilk.spot)
        // 100,000 * 10 ** 45 (100K SAI locked) <= 1 * 10 ** 50 (passes, just 1 wei can't be used)
        // 1,000,000 * 10 ** 45 (1M SAI locked) <= 10 * 10 ** 50 (passes, just 10 wei can't be used)
        // 10,000,000 * 10 ** 45 (10M SAI locked) <= 100 * 10 ** 50 (passes, just 100 wei can't be used)
        this.file(address(vat), bytes32("SAI"), bytes32("spot"), 10 ** 50);

        // Total debt ceiling (100M)
        this.file(address(vat), bytes32("Line"), 100000000 * 10 ** 45);

        // Set SAI debt ceiling (100M)
        this.file(address(vat), bytes32("SAI"), bytes32("line"), 100000000 * 10 ** 45);

        // Create Migration Contract
        migration = new SaiDaiMigration(address(saiJoin), address(daiJoin), address(vat));

        // Give access to the special authed SAI collateral to Migration contract
        saiJoin.rely(address(migration));
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

}
