pragma solidity 0.5.11;

import { GemLike, JoinLike, VatLike } from "./Interfaces.sol";

contract SaiDaiMigration {
    JoinLike                    public saiJoin;
    JoinLike                    public daiJoin;
    VatLike                     public vat;

    constructor(
        address saiJoin_,       // MCD SAI collateral adapter contract address
        address daiJoin_,       // MCD DAI adapter contract address
        address vat_            // MCD VAT contract address
    ) public {
        saiJoin = JoinLike(saiJoin_);
        daiJoin = JoinLike(daiJoin_);
        vat = VatLike(vat_);

        saiJoin.gem().approve(address(saiJoin), uint(-1));
        daiJoin.dai().approve(address(daiJoin), uint(-1));
        vat.hope(address(daiJoin));
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    // Function to swap SAI to DAI
    // This function is to be used by users that want to get new DAI in exchange of old one (aka SAI)
    // wad amount has to be <= the value pending to reach the debt ceiling (the minimum between general and ilk one)
    function swapSaiToDai(
        uint wad
    ) external {
        // Get wad amount of SAI from user's wallet:
        saiJoin.gem().transferFrom(msg.sender, address(this), wad);
        // Join the SAI wad amount to the `vat`:
        saiJoin.join(address(this), wad);
        // Lock the SAI wad amount to the CDP and generate the same wad amount of DAI
        vat.frob(saiJoin.ilk(), address(this), address(this), address(this), toInt(wad), toInt(wad));
        // Send DAI wad amount as a ERC20 token to the user's wallet
        daiJoin.exit(msg.sender, wad);
    }

    // Function to swap DAI to SAI
    // This function is to be used by users that want to get SAI in exchange of DAI
    // wad amount has to be <= the amount of SAI locked (and DAI generated) in the migration contract SAI CDP
    function swapDaiToSai(
        uint wad
    ) external {
        // Get wad amount of DAI from user's wallet:
        daiJoin.dai().transferFrom(msg.sender, address(this), wad);
        // Join the DAI wad amount to the vat:
        daiJoin.join(address(this), wad);
        // Payback the DAI wad amount and unlocks the same value of SAI collateral
        vat.frob(saiJoin.ilk(), address(this), address(this), address(this), -toInt(wad), -toInt(wad));
        // Send SAI wad amount as a ERC20 token to the user's wallet
        saiJoin.exit(msg.sender, wad);
    }

}
