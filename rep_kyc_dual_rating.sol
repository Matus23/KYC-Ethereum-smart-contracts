pragma solidity >=0.4.22 <0.6.0;

/*
 * This contract simulates the Know-Your-Customer process that needs to be 
 * executed by financial institutions before conducting business with a customer
 * It uses Ethereum blockchain in order to decrease the financial costs associated with process.
 * It assumes blockchain it is implemented on is private and is only accessible by the regulator
 * Note: terms 'bank' and 'financial institution' are used in this document interchangeably
*/

contract KYC {
    
    /**
     * @property document_package_hash - hash of the customer's document package
     * @property registered - determines whether a customer has been rgistered by a fin. inst.
     * @property customer_balance - represents balance of each customer that is to be redistributed between the fin. inst. 
                                    operating with the customer in a fair way  
     * @property kyc_price - cost of executing a single KYC for this customer   
     * @property cumulative_kyc_cost - cumulative cost of executing KYC's for this customer  
     * @property repeat_probability - probability with which KYC ought to be repeated  
     * @property kyc_count - counts # fin. inst. operating with this customer
     * @property rating_average - average rating of this customer as assigned by the fin. inst. operating with the customer  
     * @property rating_cumulative - sum of all ratings assigned to this customer by fin. inst. operating with the customer 
     * @property rating_count - # fin. inst. that assigned rating to this customer  
     * @property ratings - ratings of the customer as assigned by fin. inst. operating with the customer  
     * @property kyc_institutions - mapping of the institutions that executed KYC for this customer
     */ 
    struct Customer {
        bytes32 document_package;
        bool registered;
        uint customer_balance;
        uint kyc_price;
        uint cumulative_kyc_cost;
        uint repeat_probability;
        uint kyc_count;
        uint rating_average;                    // average rating describing how satisfied fin. inst. with the customer
        uint rating_cumulative;
        uint rating_count;                      // because some institutions might not give customer rating
        mapping (uint => uint) ratings;         // mapping: bank account id => rating value
        mapping (uint => bool) kyc_institutions; // mapping of the institutions that executed KYC for this customer
        //uint[] kyc_institutions;                // ids of institutions that executed KYC for this customer
    }

    /**
     * Bank's account to operate with a customer. A bank uses a unique account for dealing with each customer
     * @property account_address - public key of an account the bank is using for dealing with a customer
     * @property id - unique identificator for this bank account
     * @property exists - specifies whether this bank accounts exists
     * @property executed_kyc - identifies whether institution behind this account had to execute the core KYC for the associated customer
     * @property debts - mapping from bank account ids (ids of back accounts this account is owing to) to the debts' values
     */ 
    struct BankAccount {
        address payable account_address;
        uint id;
        bool exists;
        //bool executed_kyc;  --> dont need anymore, remembers which institutions executed KYC for a customer directly at the customer
        mapping (uint => uint) debts;
    }

    /**
     * @property bank_address - address of the bank on the blockchain
     * @property id - unique identificator for the bank
     * @property rating_average - average rating of this fin. inst. as assigned by other fin. inst.
     * @property rating_cumulative - cumulative rating of this fin. inst. assgined by other fin. inst. 
     * @property rating_count - # other banks that assigned a rating to this bank
     * @property bank_accounts - bank accounts' ids this bank is holding to operate with its customers
     * @property account_addresses - addresses of the bank accounts this bank is using to operate with its customers
     * @property ratings - ratings this bank assigns to other banks
     * @property customers - mapping of all customers this financial institution is operating with
     */
    struct Bank {
        address payable bank_address;
        uint id;
        bool registered;
        uint rating_average;
        uint rating_cumulative;
        uint rating_count;
        //uint[] bank_accounts;            // array of bank account ids this bank possesses
        //address[] account_addresses;     // array of addresses of the bank accounts
        mapping (uint => uint) ratings;    // mapping: bank id => rating value
        mapping (uint => bool) customers;  // mapping: customer id => true/false (whether this bank operates with the customer)
    }

    // contract owner
    address payable private contract_owner;

    // (customer_id => BankAccount[]) each customer has an array of bank accounts they are operating with  
    mapping (uint => BankAccount[]) public onboarded_list;
    // length of onboarded list of a customer
    mapping (uint => uint) public onboarded_list_length;

    // customer_id => Customer; helps retrieve info about a customer based on their id
    mapping (uint => Customer) public customers;
    // number of customers present on the blockchain
    uint public customers_length;
    
    // bank_id => Bank; helps retrieve info about a bank based on its id
    mapping (uint => Bank) public banks;

    uint8 public random_number_public;
    uint public example_debt;

    // account indices in array of customer's onboarded list
    mapping (uint => uint) account_indices_customer_array;
    // account indices in the bank accounts array that holds all available bank accounts
    mapping (uint => uint) account_indices_all_accounts;
    // mapping to check whether an account is registered
    mapping (uint => bool) account_ids;

    /**
     * Constructor initialises address of the contract owner
     */ 
    constructor() public payable {
        contract_owner = msg.sender;
    }


    /**************************************************** 
     ********************* Events ***********************
     ****************************************************/
    
    event DebtAlert (
        address payable _debtee_address,
        uint _customer_id,
        uint _debtee_id,
        uint _debt_value, 
        uint _debt_issued_date
    );

    /**************************************************** 
     ********************* Modifiers ********************
     ****************************************************/
    
    modifier only_owner{
        require(msg.sender == contract_owner, 
                "Function callable only by the regulator (contract owner)");
        _;
    }


    /**************************************************** 
     ********************* Functions ********************
     ****************************************************/
    
    /**
     * Produces a random number between <0, 100>, both ends of the interval included
     * @param customer_id - id of the customer the bank is operating with
     * @param account_id  - id of a bank account the bank is using to operate with the customer
     * @param doc_package - hash of the customer's document package
     */
    function get_random_number(uint customer_id, uint account_id, bytes32 doc_package) private view returns (uint8) {
       return uint8(uint256(keccak256(abi.encodePacked(now, block.difficulty, customer_id, account_id, doc_package)))%101);
    }

    /**
     * Produces a random number between <0, 100>, both ends of the interval included
     */
    function get_random_number() private view returns (uint8) {
       return uint8(uint256(keccak256(abi.encodePacked(now, block.difficulty)))%101);
    }
    
    /**
     * Generates a random number serving as id for the bank
     */ 
    function get_id() private view returns(uint) {
        return uint256(keccak256(abi.encodePacked(now, block.difficulty)));
    }

    /**
     * Creates a customer
     * @param id                 - customer's id
     * @param kyc_cost           - average cost of executing KYC for this customer
     * @param repeat_probability - probability with which core KYC needs to be repeated
     */ 
    function create_customer(uint id, uint kyc_cost, uint repeat_probability) public {
        require(!customers[id].registered, "Customer under this id already registered. Please choose another id");
    
        // create new customer
        customers[id] = Customer(0x000000000000000000000000000000, true, 0, kyc_cost * 1 ether, kyc_cost * 1 ether, repeat_probability, 0, 0, 0, 0);

        // increase number of customers
        customers_length++;
    }

    /**
     * Creates a bank account a bank will be using in the future to operate with arbitrary customer 
     * A bank account can be used only to operate with one customer
     * @param account_id - id of the account to be created
     * @param account_address - address of the account on the (private) blockchain
     */
    /* function create_bank_account(uint account_id, address payable account_address) public {
        // require universally unique account ids (that is, even 2 distinct banks need to have all account ids distinct as well)
        require(account_ids[account_id] == false);

        // this account id now exists
        account_ids[account_id] = true;

        // store account's index with respect to the array of all bank accounts         
        account_indices_all_accounts[account_id] = bank_accounts[bank_id].length-1;

        // assign this bank account to the bank (id & address of the account)
        banks[bank_id].bank_accounts.push(account_id);
        banks[bank_id].account_addresses.push(account_address);
    } */

    /**
     * Creates a bank 
     * @param id - id of the bank, needs to be unique
     */
    function create_bank(uint id) public {
        // verify the bank doesn't exist yet
        require(banks[id].registered == false);
                
        // create the bank
        banks[id] = Bank({
                bank_address: msg.sender, 
                id: id, 
                registered: true,
                rating_average: 0,
                rating_cumulative: 0,
                rating_count: 0
                //bank_accounts: new uint[](0),
                //account_addresses: new address[](0)
        });
    }
    
    /**
     * Assigns a rating of customer by a financial institution that represents how satisfied is the financial institution
     * with the customer in terms of executing KYC
     * @param bank_id - id of the bank that assigns rating to the customer
     * @param customer_id - id of the customer who's being rated
     * @param rating - value of the rating
     */
    function assign_customer_rating(uint bank_id, uint customer_id, uint rating) public {
        // verify rating assigned only by bank that operates with the customer
        require(banks[bank_id].customers[customer_id] == true );

        // rating between 1-10
        require( 1 <= rating && rating <= 10);
        
        // retrieve current rating value (if not initialised, will be 0)
        uint current_rating = customers[customer_id].ratings[bank_id];

        // first time rating the customer
        if (current_rating == 0) 
        {
            customers[customer_id].rating_count++;
        }
        // assign the rating
        customers[customer_id].ratings[bank_id] = rating;
    
        // update rating stats
        customers[customer_id].rating_cumulative -= current_rating;
        customers[customer_id].rating_cumulative += rating;
        customers[customer_id].rating_average = customers[customer_id].rating_cumulative / customers[customer_id].rating_count;
    }

    /**
     * Assigns rating to a financial institution by another financial institution for executing KYC
     * @param bank_id_to - id of the bank being rated
     * @param bank_id_from - id of the bank that rates the first bank
     * @param customer_id - id of the customer these two institutions both operate with
     * @param rating - value of the rating assigned
     */
    function assign_bank_rating(uint bank_id_to, uint bank_id_from, uint customer_id, uint rating) public {
        // restrict rating range (1 to 10)
        require(1 <= rating && rating <= 10, "Rating needs to be between 1 to 10");

        // check that the sender is indeed the bank that gives the rating
        require( msg.sender == banks[bank_id_from].bank_address );

        // check that the bank being rated really executed KYC for the specified customer
        require( customers[customer_id].kyc_institutions[bank_id_to]==true, "The bank that should be assigned the rating did not execute the core KYC for this customer." );

        // check whether the institution that tries to assign the rating really operated with the customer whose id is specified
        require( banks[bank_id_from].customers[customer_id]==true, "You do not operate with the specified customer." );

        // retrieve current rating (a bank might decide to assign a different rating later on)
        uint current_rating = banks[bank_id_to].ratings[bank_id_from];

        // rating doesn't exists
        if (current_rating == 0) {
            banks[bank_id_to].rating_count++;
        }

        // decrease cumulative rating by current rating (important when re-rating a bank)
        banks[bank_id_to].rating_cumulative -= current_rating;
        banks[bank_id_to].rating_cumulative += rating;
        banks[bank_id_to].ratings[bank_id_from] = rating;

        banks[bank_id_to].rating_average = banks[bank_id_to].rating_cumulative / banks[bank_id_to].rating_count;
    }
    
    /**
     * Equally distributes balance of a given customer between all onboarded institutions of this customer 
     * @param customer_id - specified customer whose balance should be redistributed
     */ 
    function distribute_contract_balance(uint customer_id) private {
        if (customers[customer_id].customer_balance > 0) {
            uint reward = customers[customer_id].customer_balance / onboarded_list[customer_id].length;
            
            // iterate through each bank account that the customer has onboarded and send appropriate reward
            for (uint i=0; i<onboarded_list[customer_id].length; i++) {
                if (customers[customer_id].customer_balance >= reward) 
                {
                    onboarded_list[customer_id][i].account_address.transfer(reward);
    
                    // decrease customer's balance 
                    customers[customer_id].customer_balance -= reward;
                }
                // could happen if integer division is not precise - would only result in minor inaccuracies
                else 
                {
                    onboarded_list[customer_id][i].account_address.transfer(customers[customer_id].customer_balance);
    
                    // set customer's balance to 0
                    customers[customer_id].customer_balance = 0;
                }
            }
        }
    }
    
    /**
     * Enters bank account of a financial institution into onboarded list of the given customer
     * @param customer_id - customer on whose onboarded list the institution is trying to get
     * @param account_id - id of the account that will enter the customer's onboarded list
     * @param bank_id - id of the bank holding the bank account
     * @param doc_package - hash of the document package of the customer
     */ 
    function enter_customers_onboarded_list(uint customer_id, uint account_id, uint bank_id, bytes32 doc_package) public payable {
        // require each bank account to have a unique account id
        require(account_ids[account_id] == false);
        // check that given bank account not already operating with the customer
        require( check_customer_and_bank_account(customer_id, account_id, msg.sender), "This bank account is already registered with the customer" );

        // account id now assigned
        account_ids[account_id] = true;

        // at least one institution already onboarded
        if (onboarded_list[customer_id].length > 0 )
        {
            // require fee based on how many fin. inst. operate with the customer
            require(msg.value >= customers[customer_id].cumulative_kyc_cost / (onboarded_list[customer_id].length + 1), "You need to pay appropriate fee");
            
            // increment balance assigned to the customer
            customers[customer_id].customer_balance += msg.value;
    
            // distribute customer's balance across other financial institutions
            distribute_contract_balance(customer_id);
    
            // retrieve account index in the array holding all bank accounts
            uint account_index = account_indices_all_accounts[account_id];

            // onboard the bank account
            //onboarded_list[customer_id].push(
            //    bank_accounts[bank_id][account_index]
            //);
            // store account index under the customer's onboarded list so it can be easily retrieved by account id
            account_indices_customer_array[account_id] = onboarded_list[customer_id].length-1;
            
            // increment counter
            onboarded_list_length[customer_id]++;
            
            // get random number in interval <0,100> based on customer's id and bank account id
            uint8 random_number = get_random_number(customer_id, account_id, customers[customer_id].document_package);
            
            // repeat KYC
            if (random_number <= customers[customer_id].repeat_probability) {
                // assign this institution to the mapping of institutions that executed KYC for this customer
                customers[customer_id].kyc_institutions[bank_id] = true;

                // increase cumulative KYC price
                customers[customer_id].cumulative_kyc_cost += customers[customer_id].kyc_price;
                
                // increase counter 
                customers[customer_id].kyc_count++;

                // price to be paid for having to repeat KYC is KYC_PRICE / # onboarded bank accounts (including the one currently getting onboarded)
                uint debt_value = customers[customer_id].kyc_price / (onboarded_list[customer_id].length);
    
                // loop through onboarded bank accounts of the customer
                for (uint account_ind=0; account_ind<onboarded_list[customer_id].length; account_ind++) {
    
                    // increase debt value owed to the account being currently onboarded by debt_value; all account_ind will owe to account_id
                    onboarded_list[customer_id][account_ind].debts[account_id] += debt_value;
                    
                    // emit debt alert 
                    emit DebtAlert(msg.sender, customer_id, account_id, debt_value, now);
                }
            }
        }
        // no institution onboarded
        else 
        {  
            require(msg.value == 0, "You are the first institution to operate with the customer. No fee required.");
            require(doc_package != 0x0, "Provided document package cannot be empty.");

            // initialise the document package for the customer
            customers[customer_id].document_package = doc_package;    

            // increase counter 
            customers[customer_id].kyc_count++;

            // assign this institution to the mapping of institutions that executed KYC for this customer
            customers[customer_id].kyc_institutions[bank_id] = true;

            // distribute customer's balance across other financial institutions
            distribute_contract_balance(customer_id);

            // retrieve account index in the array holding all bank accounts
            uint account_index = account_indices_all_accounts[account_id];

            // onboard the bank account
            onboarded_list[customer_id].push(
                bank_accounts[bank_id][account_index]
            );

            // store account index under the customer's onboarded list so it can be easily retrieved by account id
            account_indices_customer_array[account_id] = onboarded_list[customer_id].length-1;
            
            // increment counter
            onboarded_list_length[customer_id]++;
        }
    }

    /**
     * Checks whether a given bank account is already on a given customer's onboarded list
     * Note: same account id might be used when requested by a different bank account (i.e. with
     * a different address)
     * @param customer_id - id of customer to be checked 
     * @param account_id  - id of bank account to be checked 
     * @param bank_account_address - address of the bank account to be checked 
     */ 
    function check_customer_and_bank_account(uint customer_id, uint account_id, address bank_account_address) view private returns (bool) {
        for (uint i=0; i<onboarded_list[customer_id].length; i++) {
            if (onboarded_list[customer_id][i].id == account_id && onboarded_list[customer_id][i].account_address == bank_account_address) {
                return false;
            }
        }
        
        return true;
    }

    /**
     * Debtor - pays the debt
     * Debtee - is owed the debt
     * Pays a given amount of debt from debtor to debtee, i.e. searches onboarded list of 
     * customer to find debtee's bank account, then within debtee's bank account debts find's debtor's debt
     * and decreases the amount of debt by value paid
     * @param debtee_account_id - bank's account id of bank that is owed
     * @param debtor_account_id - bank's account id of bank that owes 
     * @param customer_id       - id of customer for whom this is relevant
     */
    function pay_debt(uint debtee_account_id, uint debtor_account_id, uint customer_id, address payable debtee_address) public payable 
    {
        for (uint account_ind=0; account_ind < onboarded_list[customer_id].length; account_ind++) {
            // account found
            if ( onboarded_list[customer_id][account_ind].id == debtor_account_id ) 
            {
                if (msg.value > onboarded_list[customer_id][account_ind].debts[debtee_account_id]) {
                    onboarded_list[customer_id][account_ind].debts[debtee_account_id] = 0;
                }
                else {
                    // subtract given value from the current debt
                    onboarded_list[customer_id][account_ind].debts[debtee_account_id] -= msg.value;
                }
                
                // send money to the debtee
                debtee_address.transfer(msg.value);
            }
        }
    }
    
    function get_debt_value(uint debtee_account_id, uint debtor_account_id, uint customer_id) public {
        for (uint account_ind=0; account_ind < onboarded_list[customer_id].length; account_ind++) {
            // account found
            if ( onboarded_list[customer_id][account_ind].id == debtor_account_id ) 
            {
                // subtract given value from the current debt
                example_debt = onboarded_list[customer_id][account_ind].debts[debtee_account_id];
            }
        }
    }

    /**
     * Assigns a bank account to a given bank
     */
    function assign_bank_account_to_bank(uint bank_id) public {
        // retrieve bank index
        //uint bank_index = bank_indices[bank_id];

        // assign bank account to the bank
        //banks[bank_index].bank_accounts.push(bank_id);
        //banks[bank_index].account_addresses.push(msg.sender);
    }
    
}