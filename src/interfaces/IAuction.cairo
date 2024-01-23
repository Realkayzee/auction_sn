use starknet::ContractAddress;

#[starknet::interface]
trait IAuction<TContractState> {
    fn create_auction(ref self: TContractState, token_id: u256, bid_price: u256, start_time: u32, end_time: u32);
    fn bid(ref self: TContractState, amount: u256, auction_id: u32);
    fn claim_unsuccesful_auction(ref self: TContractState, auction_id: u32);
    fn check_highest_bidder(self: @TContractState, auction_id: u32) -> BidderDetails;
    fn withdraw(ref self: TContractState, auction_id: u32);
    fn claim_auctioned_item(ref self: TContractState, auction_id: u32);
    fn check_auctions(self: @TContractState) -> Array<BidDetails>;
}

#[derive(Drop, Copy, Serde)]
struct BidderDetails {
    address: ContractAddress,
    amount_bid: u256,
}


#[derive(Drop, Serde, Copy, starknet::Store)]
struct BidDetails {
    creator: ContractAddress, // auction creator
    token_id: u256, //asset token id
    bid_price: u256,
    highest_bidder: ContractAddress,
    start_time: u32,
    end_time: u32,
    successful: bool,
    claimed: bool
}