use starknet::ContractAddress;

#[starknet::interface]
trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, to: ContractAddress, amount: u256);
    fn transfer_from(ref self: TContractState, from: ContractAddress, to: ContractAddress, amount: u256);
    fn allowance(self: @TContractState, from: ContractAddress, to: ContractAddress) -> u256;
}