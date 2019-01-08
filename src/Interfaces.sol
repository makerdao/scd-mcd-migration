/// Interfaces.sol

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

contract GemLike {
    function balanceOf(address) public view returns (uint);
    function approve(address) public;
    function approve(address, uint) public;
    function transfer(address, uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function move(address, address, uint) public;
    function withdraw(uint) public;
}

contract ValueLike {
    function peek() public returns (bytes32, bool);
}

contract SaiTubLike {
    function gem() public view returns (GemLike);
    function skr() public view returns (GemLike);
    function gov() public view returns (GemLike);
    function sai() public view returns (GemLike);
    function pep() public view returns (ValueLike);
    function bid(uint) public view returns (uint);
    function lad(bytes32) public view returns (address);
    function tab(bytes32) public view returns (uint);
    function rap(bytes32) public view returns (uint);
    function ink(bytes32) public view returns (uint);
    function per() public view returns (uint);
    function shut(bytes32) public;
    function exit(uint) public;
    function give(bytes32, address) public;
}

contract EthJoinLike {
    function join(bytes32) public payable;
}

contract JoinLike {
    function gem() public returns (GemLike);
    function dai() public returns (GemLike);
    function join(bytes32, uint) public;
    function exit(bytes32, address, uint) public;
}
contract VatLike {
    function ilks(bytes32) public view returns (uint, uint);
}

contract PitLike {
    function frob(bytes32, bytes32, bytes32, bytes32, int, int) public;
    function vat() public view returns (VatLike);
}

contract ManagerLike {
    function getUrn(bytes12) public view returns (bytes32);
    function open() public returns (bytes12);
    function frob(address, bytes12, bytes32, int, int) public;
    function exit(address, bytes12, address, uint) public;
    function move(bytes12, address) public;
}
