pragma solidity >=0.5.0;

import {DSNote} from "ds-note/note.sol";

contract GemLike {
    function transfer(address,uint) public returns (bool);
    function transferFrom(address,address,uint) public returns (bool);
}

contract VatLike {
    function slip(bytes32,address,int) public;
    function move(address,address,uint) public;
    function flux(bytes32,address,address,uint) public;
}

contract AuthGemJoin is DSNote {
    VatLike public vat;
    bytes32 public ilk;
    GemLike public gem;

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) public note auth { wards[usr] = 1; }
    function deny(address usr) public note auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1, "AuthGemJoin/non-authed"); _; }

    constructor(address vat_, bytes32 ilk_, address gem_) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = GemLike(gem_);
        wards[msg.sender] = 1;
    }

    function join(address usr, uint wad) public auth note {
        require(int(wad) >= 0, "AuthGemJoin/overflow");
        vat.slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "AuthGemJoin/failed-transfer");
    }

    function exit(address usr, uint wad) public auth note {
        require(wad <= 2 ** 255, "AuthGemJoin/overflow");
        vat.slip(ilk, msg.sender, -int(wad));
        require(gem.transfer(usr, wad), "AuthGemJoin/failed-transfer");
    }
}
