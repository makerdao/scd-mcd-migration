# MCDMigrator

This allows you to do two things:

* Exchange your SAI for DAI
* Migrate a CDP from SCD to MCD

## Exchanging SAI for SAI

The steps are:

* `allow` the SAI adapter
* `MCDMigrator.swapSaiToDai`

## Migrating a CDP

Migrating a CDP from SCD to MCD means going from a `(WETH, SAI)` CDP to a
`(WETH, DAI)` CDP, i.e. converting Sai to Dai and moving the WETH.

A high-level description of the process follows:

* User calls `ProxyLib.migrate` via its proxy
  * MKR funds for the CDP's stability fees are sent to the migrator
  * SCD CDP is transferred to the migrator
* Migrator repays and closes user's SCD CDP
* Migrator creates MCD CDP
* Migrator transfers WETH to MCD CDP
* Migrator withdraws from CDP the debt it is owed
* Migrator transfers MCD CDP to user
