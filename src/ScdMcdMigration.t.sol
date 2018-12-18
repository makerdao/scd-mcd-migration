pragma solidity ^0.4.24;

import "ds-test/test.sol";

import "./ScdMcdMigration.sol";

contract ScdMcdMigrationTest is DSTest {
    ScdMcdMigration migration;

    function setUp() public {
        migration = new ScdMcdMigration();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
