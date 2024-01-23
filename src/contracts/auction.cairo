#[starknet::contract]
mod Auction {
    use core::array::ArrayTrait;
use core::traits::Into;
use core::option::OptionTrait;
use core::traits::TryInto;
use core::starknet::event::EventEmitter;
use starknet::{ ContractAddress, get_caller_address, get_contract_address, get_block_timestamp };
    use auction::interfaces::IERC20::{ IERC20Dispatcher, IERC20DispatcherTrait };
    use auction::interfaces::IERC721::{ IERC721Dispatcher, IERC721DispatcherTrait };
    use auction::interfaces::IAuction::{ IAuction, BidDetails, BidderDetails };
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721ReceiverComponent;

    component!(path: ERC721ReceiverComponent, storage: erc721_receiver, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // ERC721 receiver
    #[abi(embed_v0)]
    impl ERC721ReceiverImpl = ERC721ReceiverComponent::ERC721ReceiverImpl<ContractState>;
    impl ERC721ReceiverInternalImpl = ERC721ReceiverComponent::InternalImpl<ContractState>;

    // SRC5
    impl SRC5 = SRC5Component::SRC5Impl<ContractState>;

    // contract event
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AuctionCreated: AuctionCreated,
        Bid: Bid,
        Withdrawn: Withdrawn,
        Claimed: Claimed,
        ERC721Event: ERC721ReceiverComponent::Event,
        SRC5Event: SRC5Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct AuctionCreated {
        auction_id: u32,
        auction_data: BidDetails,
    }

    #[derive(Drop, starknet::Event)]
    struct Bid {
        address: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        address: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Claimed {
        address: ContractAddress,
        amount: u256
    }

    // contract storage
    #[storage]
    struct Storage {
        token: IERC20Dispatcher, // currency for bidding
        asset: IERC721Dispatcher, // asset
        auction: LegacyMap::<u32, BidDetails>,
        auction_length: u32,
        // erc721 receiver
        #[substorage(v0)]
        erc721_receiver: ERC721ReceiverComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc721_receiver.initializer();
    }

    #[abi(embed_v0)]
    impl AuctionImpl of IAuction<ContractState> {
        fn create_auction(ref self: ContractState, token_id: u256, bid_price: u256, start_time: u32, end_time: u32) {
            let creator = get_caller_address();
            let contract_addr = get_contract_address();
            // hold the asset in escrow
            self.asset.read().safe_transfer_from(creator, contract_addr, token_id);
            // compute the auction data
            let compute_bid = BidDetails {
                creator,
                token_id,
                bid_price,
                highest_bidder: creator,
                start_time,
                end_time,
                successful: false,
                claimed: false,
            };
            let index = self.auction_length.read();
            self.auction.write(index, compute_bid);
            let len = index + 1;
            self.auction_length.write(len);

            self.emit(Event::AuctionCreated(AuctionCreated {
                auction_id: index,
                auction_data: compute_bid,
            }))
        }

        fn bid(ref self: ContractState, amount: u256, auction_id: u32) {
            // cache data
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            let mut _auction = self.auction.read(auction_id);
            // check if auction is valid
            has_started_or_ended(_auction);

            if(amount > _auction.bid_price) {
                if (!_auction.successful) {
                    _auction.successful = true;
                }
                _auction.bid_price = amount;
                _auction.highest_bidder = caller;

                self.auction.write(
                    auction_id,
                    _auction
                );
            } else {
                panic!("Higher bid exists");
            }

            self.emit(Event::Bid(Bid {
                address: caller,
                amount,
            }));
        }

        fn claim_unsuccesful_auction(ref self: ContractState, auction_id: u32) {
            // cache data
            let _auction = self.auction.read(auction_id);
            let timestamp = get_block_timestamp();
            let caller = get_caller_address();
            let contract_addr = get_contract_address();

            assert!(timestamp >= _auction.end_time.into() && !_auction.successful, "AUCTION: Can't claim");
            assert!(_auction.creator == caller);
            self.asset.read().safe_transfer_from(
                contract_addr,
                caller,
                _auction.token_id
            );

            self.emit(Event::Claimed(Claimed {
                address: caller,
                amount: _auction.token_id
            }))
        }

        fn check_highest_bidder(self: @ContractState, auction_id: u32) -> BidderDetails {
            let _auction = self.auction.read(auction_id);
            let _bidderDetails = BidderDetails {
                address: _auction.highest_bidder,
                amount_bid: _auction.bid_price,
            };

            _bidderDetails
        }

        fn withdraw(ref self: ContractState, auction_id: u32) {
            let _auction = self.auction.read(auction_id);
            assert!(_auction.claimed, "Withdraw Unsuccessful");
            self.token.read().transfer(_auction.creator, _auction.bid_price);

            self.emit(Event::Withdrawn(Withdrawn {
                address: _auction.creator,
                amount: _auction.bid_price,
            }))
        }

        fn claim_auctioned_item(ref self: ContractState, auction_id: u32) {
            let _auction = self.auction.read(auction_id);
            let caller = get_caller_address();
            let contract_addr = get_contract_address();
            let timestamp = get_block_timestamp();

            assert!(caller == _auction.highest_bidder && timestamp >= _auction.end_time.into());
            self.token.read().transfer_from(caller, get_contract_address(), _auction.bid_price);
            self.asset.read().safe_transfer_from(contract_addr, caller, _auction.token_id);

            self.emit(Event::Claimed(Claimed {
                address: caller,
                amount: _auction.token_id
            }))
        }

        fn check_auctions(self: @ContractState) -> Array<BidDetails> {
            let len = self.auction_length.read();
            let mut index = 0;
            let mut _bidarray = ArrayTrait::<BidDetails>::new();

            loop {
                if (index == len) {
                    break;
                }

                let _bidDetails = self.auction.read(index);
                _bidarray.append(_bidDetails);

                index += 1;
            };

            _bidarray
        }
    }

    // Free functions
    fn has_started_or_ended(_auction: BidDetails) {
        assert!(
            _auction.start_time <= get_block_timestamp().try_into().unwrap(),
            "Auction has not started, starting in {}",
            _auction.start_time
        );
        assert!(
            _auction.end_time >= get_block_timestamp().try_into().unwrap(),
            "Auction has ended"
        );
    }
}