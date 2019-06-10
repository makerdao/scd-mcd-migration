/// ScdMcdMigration.sol

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

contract ScdMcdMigration {
    SaiTubLike                  public tub;
    address                     public vat;
    ManagerLike                 public cdpManager;
    JoinLike                    public saiJoin;
    JoinLike                    public wethJoin;
    JoinLike                    public daiJoin;
    mapping (address => uint)   public sum;

    constructor(
        address tub_, // SCD tub contract address
        address vat_, // MCD vat contract address
        address cdpManager_, // MCD manager contract address
        address saiJoin_, // MCD SAI adapter contract address
        address wethJoin_, // MCD ETH adapter contract address
        address daiJoin_ // MCD DAI adapter contract address
    ) public {
        tub = SaiTubLike(tub_);
        vat = vat_;
        cdpManager = ManagerLike(cdpManager_);
        saiJoin = JoinLike(saiJoin_);
        wethJoin = JoinLike(wethJoin_);
        daiJoin = JoinLike(daiJoin_);
        tub.gov().approve(address(tub), uint(-1));
        tub.skr().approve(address(tub), uint(-1));
        tub.sai().approve(address(tub), uint(-1));
        tub.sai().approve(address(saiJoin), uint(-1));
        wethJoin.gem().approve(address(wethJoin), uint(-1));
        daiJoin.dai().approve(address(daiJoin), uint(-1));
        VatLike(vat).hope(address(daiJoin));
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

    // Function to swap SAI to DAI
    // This function is to be used by users that want to get new DAI in exchange of old one (aka SAI)
    // wad amount has to be <= the value to reach the debt ceiling (the minimum between general and ilk one)
    function swapSaiToDai(
        uint wad
    ) external {
        // Gets wad amount of SAI from user's wallet:
        saiJoin.gem().transferFrom(msg.sender, address(this), wad);
        // Joins the SAI wad amount to the `vat`:
        saiJoin.join(address(this), wad);
        // Locks the SAI wad amount to the CDP and generates the same wad amount of DAI
        VatLike(vat).frob(bytes32(JoinLike(saiJoin).ilk()), address(this), address(this), address(this), toInt(wad), toInt(wad));
        // Sends DAI wad amount as a ERC20 token to the user's wallet
        daiJoin.exit(msg.sender, wad);
    }

    // Function to swap DAI to SAI
    // This function is to be used by users that want to get old DAI (SAI) in exchange of new one (DAI)
    // wad amount has to be <= the amount of SAI locked (and DAI generated) in the migration contract SAI CDP
    function swapDaiToSai(
        uint wad
    ) external {
        // Gets wad amount of DAI from user's wallet:
        daiJoin.dai().transferFrom(msg.sender, address(this), wad);
        // Joins the DAI wad amount to the vat:
        daiJoin.join(address(this), wad);
        // Paybacks the DAI wad amount and unlocks the same value of SAI collateral
        VatLike(vat).frob(bytes32(JoinLike(saiJoin).ilk()), address(this), address(this), address(this), -toInt(wad), -toInt(wad));
        // Sends SAI wad amount as a ERC20 token to the user's wallet
        saiJoin.exit(msg.sender, wad);
    }

    // Function to deposit DAI funds in the migration contract
    // This function is intended to be used internally. These funds are needed to make the CDP migrate funtion to work.
    // There is not benefit at all for the depositer to provide these funds to the contract.
    // IMPORTANT: Funds should not be sent directly or they will not be able to be withdrawn (only use this function)
    function vatMoveIn(uint rad) external {
        VatLike(vat).move(msg.sender, address(this), rad);
        sum[msg.sender] = add(sum[msg.sender], rad);
    }

    // Function to withdraw DAI funds from the migration contract
    function vatMoveOut(uint rad) external {
        sum[msg.sender] = sub(sum[msg.sender], rad);
        VatLike(vat).move(address(this), msg.sender, rad);
    }

    // Function to migrate a SCD CDP to MCD one (needs to be used via a proxy so the code can be kept simpler). Check ProxyLib.sol code for usage.
    // In order to use the migrate functionality the contract needs to accomplish the following 2 conditions:
    // 1. It has to have its MCD SAI CDP with a debt >= than the SCD CDP debt to migrate (to be able to balance out)
    // 2. It has to have deposited DAI funds >= than the SCD CDP debt to migrate (to be able to payback debt, so SAI can be taken out).
    //    The funds will be returned at the end when the new MCD ETH CDP of the user is created.
    function migrate(
        bytes32 cup
    ) external returns (uint cdp) {
        // Get values
        uint debtAmt = tub.tab(cup); // CDP SAI debt
        uint pethAmt = tub.ink(cup); // CDP locked collateral
        uint ethAmt = tub.bid(pethAmt); // CDP locked collateral equiv in ETH

        // Take SAI out from MCD SAI CDP. For this operation is needed that the migration contract has DAI funds deposited
        VatLike(vat).frob(
            bytes32(JoinLike(saiJoin).ilk()),
            address(this),
            address(this),
            address(this),
            -toInt(debtAmt), // debtAmt needs to be <= than the SAI deposited in this CDP
            -toInt(debtAmt) // debtAmt needs to be <= than the DAI funds deposited in the migration contract
        );
        saiJoin.exit(address(this), debtAmt); // SAI is exited as a token

        // Shut SAI CDP and gets WETH back
        tub.shut(cup); // CDP is closed using the SAI exited one line of code before and the MKR previously sent by the user (via the proxy call)
        tub.exit(pethAmt); // Converts PETH to WETH

        // Open future user's CDP in MCD
        cdp = ManagerLike(cdpManager).open(JoinLike(wethJoin).ilk());

        // Join WETH to Adapter
        // IMPORTANT: It assumes the WETH contract is the same for SCD than MCD,
        //            otherwise the code should withdraw from SCD WETH and deposit into the MCD one
        wethJoin.join(ManagerLike(cdpManager).urns(cdp), ethAmt);

        // Lock WETH in future user's CDP, generates debt to compensate funds previously used
        (, uint rate,,,) = VatLike(vat).ilks(JoinLike(wethJoin).ilk());
        ManagerLike(cdpManager).frob(
            cdp,
            toInt(ethAmt),
            toInt(mul(debtAmt, 10 ** 27) / rate + 1) // To avoid rounding issues we add an extra wei of debt
        );
        // Move DAI balance to migration contract (to recover the used funds)
        ManagerLike(cdpManager).move(cdp, address(this), mul(debtAmt, 10 ** 27));

        // Set ownership of CDP to the user
        ManagerLike(cdpManager).give(cdp, msg.sender);
    }
}
