/// ProxyLib.sol

// Copyright (C) 2018 Gonzalo Balabasquer <gbalabasquer@gmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0;

import "ds-math/math.sol";

import { SaiTubLike } from "./Interfaces.sol";
import "./ScdMcdMigration.sol";

// This contract is intended to be executed via the Profile proxy of a user (DSProxy) which owns the SCD CDP
contract ProxyLib is DSMath {
    function migrate(address payable scdMcdMigration, bytes32 cup) public returns (uint cdp) {
        SaiTubLike tub = ScdMcdMigration(scdMcdMigration).tub();
        // Transfers ownership of SCD CDP to the migration contract
        tub.give(cup, address(scdMcdMigration));
        // Gets necessary MKR fee and move it to the migration contract
        (bytes32 val, bool ok) = tub.pep().peek();
        if (ok && uint(val) != 0) {
            tub.gov().transferFrom(msg.sender, address(scdMcdMigration), wdiv(tub.rap(cup), uint(val)));
        }
        // Executes migrate function
        cdp = ScdMcdMigration(scdMcdMigration).migrate(cup);
    }
}
