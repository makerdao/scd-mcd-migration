pragma solidity 0.5.11;

import "ds-math/math.sol";

import { SaiTubLike } from "./Interfaces.sol";
import "./ScdMcdMigration.sol";

// This contract is intended to be executed via the Profile proxy of a user (DSProxy) which owns the SCD CDP
contract MigrationProxyActions is DSMath {
    function migrate(address payable scdMcdMigration, bytes32 cup) public returns (uint cdp) {
        SaiTubLike tub = ScdMcdMigration(scdMcdMigration).tub();
        // Transfer ownership of SCD CDP to the migration contract
        tub.give(cup, address(scdMcdMigration));
        // Get necessary MKR fee and move it to the migration contract
        (bytes32 val, bool ok) = tub.pep().peek();
        if (ok && uint(val) != 0) {
            tub.gov().transferFrom(msg.sender, address(scdMcdMigration), wdiv(tub.rap(cup), uint(val)));
        }
        // Execute migrate function
        cdp = ScdMcdMigration(scdMcdMigration).migrate(cup);
    }
}
