pragma solidity ^0.8.0;

interface IWrappedExternalBribeFactory {
    function oldBribeToNew(address) external returns (address);
}
