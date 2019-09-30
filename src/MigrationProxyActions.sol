pragma solidity 0.5.11;

import "ds-math/math.sol";

import { SaiTubLike, OtcLike } from "./Interfaces.sol";
import "./ScdMcdMigration.sol";

// This contract is intended to be executed via the Profile proxy of a user (DSProxy) which owns the SCD CDP
contract MigrationProxyActions is DSMath {
    function migrate(
        address payable scdMcdMigration,    // Migration contract address
        bytes32 cup,                        // SCD CDP Id to migrate
        address otc,                        // Otc address (only if gov fee will be paid with another token)
        address payGem,                     // Token address (only if gov fee will be paid with another token)
        uint maxPayAmt                      // Max amount of payGem to sell for govFee needed (only if gov fee will be paid with another token)
    ) public returns (uint cdp) {
        SaiTubLike tub = ScdMcdMigration(scdMcdMigration).tub();
        // Transfer ownership of SCD CDP to the migration contract
        tub.give(cup, address(scdMcdMigration));
        // Get necessary MKR fee and move it to the migration contract
        (bytes32 val, bool ok) = tub.pep().peek();
        if (ok && uint(val) != 0) {
            // Calculate necessary value of MKR to pay the govFee
            uint govFee = wdiv(tub.rap(cup), uint(val));

            if (otc != address(0) && payGem != address(0)) {
                // If otc and payGem addrs are present process the trade
                // Calculate how much payGem is needed for getting govFee value
                uint payAmt = OtcLike(otc).getPayAmount(payGem, address(tub.gov()), govFee);
                // Fails if exceeds maximum
                require(maxPayAmt >= payAmt, "maxPayAmt-exceeded");
                // Set allowance, if necessary
                if (GemLike(payGem).allowance(address(this), otc) < payAmt) {
                    GemLike(payGem).approve(otc, payAmt);
                }
                // Get payAmt of payGem from user's wallet
                require(GemLike(payGem).transferFrom(msg.sender, address(this), payAmt), "transfer-failed");
                // Trade it for govFee amount of MKR
                OtcLike(otc).buyAllAmount(address(tub.gov()), govFee, payGem, payAmt);
                // Transfer govFee amount of MKR to Migration contract
                require(tub.gov().transfer(address(scdMcdMigration), govFee), "transfer-failed");
            } else {
                // Else get MKR from the user's wallet and transfer to Migration contract
                require(tub.gov().transferFrom(msg.sender, address(scdMcdMigration), govFee), "transfer-failed");
            }
        }
        // Execute migrate function
        cdp = ScdMcdMigration(scdMcdMigration).migrate(cup);
    }
}
