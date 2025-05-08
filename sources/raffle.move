
module raffle::raffle{
  use sui::transfer;
  use sui::object::{Self,ID, UID};
  use sui::tx_context::{Self, TxContext};
  use sui::table::{Self,Table};
  use std::string;
  use sui::balance::{Self, Balance};
  use sui::coin::{Self, Coin};
  //use sui::clock::{Self, Clock};
  ///use std::debug;

  struct Raffle<phantom T> has key{
    id: UID,
    name: string::String,
    image: string::String,
    spots: u64,
    state: bool,
    price: u64,
    ends_in: u64,
    funds: Balance<T>,
    addresses: Table<address,u64>
  }

  struct AdminCap has key, store {
        id: UID,
        raffle_id: ID,
  }

  const ENO_STOPPED: u64 = 0;
  const ENO_SPOTS: u64 = 1;
  const EAdminOnly: u64 = 3;
  const EWithdrawTooLarge: u64 = 4;

  public entry fun create_raffle<T>(name: vector<u8>,image: vector<u8>,spots: u64, price: u64,ends_in: u64,ctx: &mut TxContext){
    let id = object::new(ctx);
    let raffle_id = object::uid_to_inner(&id);
    transfer::share_object(Raffle<T> {
            id: id,
            name: string::utf8(name),
            image: string::utf8(image),
            spots: spots,
            state: true,
            price: price, // in $ HOMI
            ends_in: ends_in,
            funds: balance::zero<T>(),
            addresses: table::new<address,u64>(ctx)
    });
    transfer::transfer(AdminCap { id: object::new(ctx), raffle_id }, tx_context::sender(ctx))
  }

  public entry fun join_raffle<T>(raffle: &mut Raffle<T>,price: Coin<T>,ctx: &mut TxContext){
    assert!(raffle.state,ENO_STOPPED);
    assert!(raffle.spots > 0,ENO_SPOTS);
    assert!(coin::value(&price) >= raffle.price,ENO_SPOTS);
    let sender = tx_context::sender(ctx);
    if(!table::contains(&raffle.addresses,sender)){
      table::add(&mut raffle.addresses,sender,1);
    };/*else{
      let count = table::borrow_mut(&mut raffle.addresses,sender);
      count = &mut 2;
    };*/
    raffle.spots = raffle.spots - 1;
    coin::put(&mut raffle.funds, price)
  }

  public entry fun withdraw<T>(
        raffle: &mut Raffle<T>,
        admin_cap: &AdminCap,
        amount: u64,
        ctx: &mut TxContext
    ){
        // only the holder of the `AdminCap` for `self` can withdraw funds
        assert!(object::borrow_id(raffle) == &admin_cap.raffle_id, EAdminOnly);

        let to_withdraw = &mut raffle.funds;
        assert!(balance::value(to_withdraw) >= amount, EWithdrawTooLarge);
        let withdraw_coins = coin::take(to_withdraw, amount, ctx);
        transfer::public_transfer(withdraw_coins, tx_context::sender(ctx))
  }

  public entry fun update_state<T>(
        raffle: &mut Raffle<T>,
    ) {
        raffle.state = !raffle.state
    }

  #[test_only]
    public fun init_for_testing<T>(name: vector<u8>,image: vector<u8>,spots: u64, price: u64,ends_in: u64,ctx: &mut TxContext) {
        create_raffle<T>(name,image,spots,price,ends_in,ctx);
    }
    public fun raffle_spots<T>(raffle: &Raffle<T>): u64 {
        raffle.spots
    }

}

#[test_only]
  module sui::raffle_test {
    use sui::test_scenario as ts;
    //use sui::transfer;
    //use std::string;
    //use sui::clock::{Self, Clock};
    use basics::raffle::{Self,Raffle,AdminCap};
    use sui::coin::{Self,Coin};
    use sui::sui::SUI;
    #[test]
    fun raffle_test() {
        let addr1 = @0xA;
        //let addr2 = @0xB;
        // create the NFT
        let scenario = ts::begin(addr1);
        {
            raffle::init_for_testing<SUI>(b"test",b"test",1,100,0, ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, addr1);
        {
           let raffle = ts::take_shared<Raffle<SUI>>(&mut scenario);
           let sui = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
           let cap = ts::take_from_sender<AdminCap>(&mut scenario);
           raffle::join_raffle<SUI>(&mut raffle,sui,ts::ctx(&mut scenario));
           assert!(raffle::raffle_spots(&raffle) == 0,5);
           assert!(!ts::has_most_recent_for_sender<Coin<SUI>>(&mut scenario),0);  
           raffle::withdraw(&mut raffle,&cap,100,ts::ctx(&mut scenario));
           raffle::update_state(&mut raffle);
           ts::return_to_sender(&mut scenario,cap);
           ts::return_shared(raffle);
        };

        ts::end(scenario);
    }
    
}
