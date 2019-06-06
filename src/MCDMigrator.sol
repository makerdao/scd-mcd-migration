/// MCDMigrator.sol

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

import {SaiTubLike, ManagerLike, JoinLike, GemLike, VatLike} from "./Interfaces.sol";

contract MCDMigrator {
    SaiTubLike                  public tub;
    VatLike                     public vat;
    ManagerLike                 public cdpManager;
    JoinLike                    public saiJoin;
    JoinLike                    public wethJoin;
    JoinLike                    public daiJoin;
    mapping (address => uint)   public gems;

    constructor(
        address tub_, // SCD tub contract address
        address vat_, // MCD vat contract address
        address cdpManager_, // MCD manager contract address
        address saiJoin_, // MCD SAI adapter contract address
        address wethJoin_, // MCD ETH adapter contract address
        address daiJoin_ // MCD DAI adapter contract address
    ) public {
        tub = SaiTubLike(tub_);
        vat = VatLike(vat_);
        cdpManager = ManagerLike(cdpManager_);
        saiJoin  = JoinLike(saiJoin_);
        wethJoin = JoinLike(wethJoin_);
        daiJoin  = JoinLike(daiJoin_);
        tub.gov().approve(address(tub), uint(-1));
        tub.skr().approve(address(tub), uint(-1));
        tub.sai().approve(address(tub), uint(-1));
        tub.sai().approve(address(saiJoin), uint(-1));
        wethJoin.gem().approve(address(wethJoin), uint(-1));
        daiJoin.dai().approve(address(daiJoin), uint(-1));
        vat.hope(address(daiJoin));
    }

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "add-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-underflow");
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    // Swap SAI with DAI.
    // wad must be <= min(Line, ilks["sai"].line)
    function sai2dai(
        uint wad
    ) external {
        // Gets wad amount of SAI from user's wallet:
        saiJoin.gem().transferFrom(msg.sender, address(this), wad);
        // Joins the SAI wad amount to the `vat`:
        saiJoin.join(address(this), wad);
        // Locks the SAI wad amount to the CDP and generates the same wad amount of DAI
        vat.frob(bytes32(JoinLike(saiJoin).ilk()), address(this), address(this), address(this), toInt(wad), toInt(wad));
        // Sends DAI wad amount as a ERC20 token to the user's wallet
        daiJoin.exit(msg.sender, wad);
    }

    // Swap DAI with SAI.
    // wad must be <= the amount of SAI locked (and DAI generated) in the migration contract SAI CDP
    function dai2sai(
        uint wad
    ) external {
        // Gets wad amount of DAI from user's wallet:
        daiJoin.dai().transferFrom(msg.sender, address(this), wad);
        // Joins the DAI wad amount to the vat:
        daiJoin.join(address(this), wad);
        // Paybacks the DAI wad amount and unlocks the same value of SAI collateral
        vat.frob(bytes32(JoinLike(saiJoin).ilk()), address(this), address(this), address(this), -toInt(wad), -toInt(wad));
        // Sends SAI wad amount as a ERC20 token to the user's wallet
        saiJoin.exit(msg.sender, wad);
    }

    // Function to deposit DAI funds in the migration contract
    // This function is intended to be used internally. These funds are needed to make the CDP migrate funtion to work.
    // There is not benefit at all for the depositer to provide these funds to the contract.
    // IMPORTANT: Funds should not be sent directly or they will not be able to be withdrawn (only use this function)
    function vatMoveIn(uint rad) external {
        vat.move(msg.sender, address(this), rad);
        gems[msg.sender] = add(gems[msg.sender], rad);
    }

    // Function to withdraw DAI funds from the migration contract
    function vatMoveOut(uint rad) external {
        gems[msg.sender] = sub(gems[msg.sender], rad);
        vat.move(address(this), msg.sender, rad);
    }

    // Migrates a CDP from SCD to MCD.
    // NOTE: Needs to be used via a proxy so the code can be kept simpler. Check
    // ProxyLib.sol for usage.
    // This contract's MCD SAI CDP must fulfill the following two conditions:
    // * have an unlocked DAI debt >= than the SAI to migrate
    // * have a locked SAI balance >= than the SAI to migrate
    function migrate(
        bytes32 cup
    ) external returns (uint cdp) {
        // Get values
        uint debtAmt = tub.tab(cup);     // SCD CDP debt              (SAI)
        uint pethAmt = tub.ink(cup);     // SCD CDP locked collateral (PETH)
        uint ethAmt  = tub.bid(pethAmt); // SCD CDP locked collateral (ETH)

        // Take SAI out from MCD SAI CDP.
        // For this operation it's necessary that the MCDMigrator has enough
        // DAI to repay `debtAmt`
        vat.frob(
            bytes32(JoinLike(saiJoin).ilk()),
            address(this),
            address(this),
            address(this),
            // debtAmt needs to be <= than the SAI deposited in this CDP
            -toInt(debtAmt),
            // debtAmt needs to be <= than the DAI funds deposited in the migration contract
            -toInt(debtAmt)
        );
        // exit SAI as an ERC20 token
        saiJoin.exit(address(this), debtAmt);

        // Shut SAI CDP and get WETH back.
        // The CDP is closed using the SAI `exit`ed above and the MKR previously sent by the user via the proxy call
        tub.shut(cup);
        // Convert PETH to WETH
        tub.exit(pethAmt);

        // Open user's CDP in MCD
        cdp = cdpManager.open(wethJoin.ilk());

        // Join WETH into Adapter
        // IMPORTANT: This assumes the WETH contract is the same for SCD and MCD.
        wethJoin.join(cdpManager.urns(cdp), ethAmt);

        // Lock WETH in the MCD CDP, and generate debt to compensate for the
        // funds used previously
        (, uint rate,,,) = vat.ilks(wethJoin.ilk());
        cdpManager.frob(
            cdp,
            toInt(ethAmt),
            // To avoid rounding issues we add an extra wei of debt
            toInt(mul(debtAmt, 10 ** 27) / rate + 1)
        );
        // Move DAI balance to migration contract (to recover the used funds)
        cdpManager.move(cdp, address(this), mul(debtAmt, 10 ** 27));

        // Set ownership of CDP to the user
        cdpManager.give(cdp, msg.sender);
    }
}
