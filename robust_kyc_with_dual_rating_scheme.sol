pragma solidity >=0.4.22 <0.6.0;

/*
 * This contract simulates Robust Know-Your-Customer process that needs to be 
 * executed by financial institutions before conducting business with a customer
 * The contract should be deployed on a private permissioned blockchain
 * @author - Matus Drgon
*/

contract KYC {
    

     /** Customer profile
     * @property document_package_hash - hash of the customer's document package
     * @property id - customer's unique id
     * @property registered - determines whether a customer has been rgistered by a fin. inst.
     * @property require_update - if true, customer's KYC requires to be updated (set by regulator)
     * @property update_in_progress - if true, customer's KYC update being executed by a financial institution 
     * @property customer_balance - represents balance of each customer that is to be redistributed between the fin. inst. 
                                    operating with the customer in a fair way  
     * @property kyc_price - cost of executing a single KYC for this customer   
     * @property cumulative_kyc_cost - cumulative cost of executing KYC's for this customer  
     * @property repeat_probability - probability with which KYC ought to be repeated  
     * @property kyc_count - counts # fin. inst. operating with this customer
     * @property rating_average - average rating of this customer describing how satisfied fin. inst. are with the customer
     * @property rating_cumulative - sum of all ratings assigned to this customer by fin. inst. operating with the customer 
     * @property rating_count - # fin. inst. that assigned rating to this customer  
     * @property ratings - ratings of the customer as assigned by fin. inst. operating with the customer (mapping: bank account id => rating value)
     */ 
    struct Customer {
        bytes32 document_package_hash;
        uint id;
        bool registered;
        bool require_update;
        bool update_in_progress;
        uint customer_balance;
        uint kyc_price;
        uint cumulative_kyc_cost;
        uint repeat_probability;
        uint kyc_count;
        uint rating_average;                   
        uint rating_cumulative;
        uint rating_count;                      
        mapping (uint => uint) ratings;         
    }

    /**
     * Bank's account to operate with a customer. A bank uses a unique account for dealing with each customer
     * @property account_address - public key of an account the bank is using for dealing with a customer
     * @property id - unique identificator for this bank account
     * @property exists - whether this bank account is registered
     * @property debts - mapping from bank account ids (ids of back accounts this account is owing to) to the debts' values
     */ 
    struct BankAccount {
        address payable account_address;
        uint id;
        bool exists;
        mapping (uint => uint) debts;
    }

    /**
     * @property bank_address - address of the bank on the blockchain
     * @property id - unique identificator for the bank
     * @property rating_average - average rating of this fin. inst. as assigned by other fin. inst.
     * @property rating_cumulative - cumulative rating of this fin. inst. assgined by other fin. inst. 
     * @property rating_count - # other banks that assigned a rating to this bank
     * @property ratings - ratings this bank assigns to other banks
     * @property customers - mapping of all customers this financial institution is operating with
     * @property kyc_executions - mapping of all customers this bank executed KYC for (mapping: customer id => true/false)
     * @property kyc_update_flags - mapping of all customers for which the bank should execute a KYC update
     */
    struct Bank {
        address payable bank_address;
        uint id;
        bool registered;
        uint rating_average;
        uint rating_cumulative;
        uint rating_count;
        mapping (uint => uint) ratings;    // mapping: bank id => rating value
        mapping (uint => bool) customers;  // mapping: customer id => true/false (whether this bank operates with the customer)
        mapping (uint => bool) kyc_executions;  // mapping: customer id => true/false (whether this bank executed KYC for the customer)
        mapping (uint => bool) kyc_update_flags;
    }

    // contract owner == regulator
    address payable private regulator;

    // (customer_id => BankAccount[]) each customer has an array of bank accounts they are operating with  
    mapping (uint => BankAccount[]) public onboarded_list;
    // length of onboarded list of a customer
    mapping (uint => uint) public onboarded_list_length;

    mapping (uint => Customer) public customers;
    uint public customers_length;

    mapping (uint => Bank) public banks;

    uint8 public random_number_public;
    uint public example_debt;

    // mapping of bank account id to index in the array (to easily retrieve a bank account from the array)
    mapping (uint => uint) account_indices;
    // mapping of bank account ids to keep track of already used ids
    mapping (uint => bool) account_ids;
    // mapping of bank account address to id of the account
    mapping (address => uint) address_to_id;

    // initial value for update constant
    uint public update_constant = 1;

    /**
     * Constructor initialises address of the contract owner
     */ 
    constructor() public payable {
        regulator = msg.sender;
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
    
    event RepeatKYC (
        uint _account_id,
        bytes32 _document_package_hash
    );

    event KYCUpdateRequired (
        uint _customer_id
    );

    event KYCFailureAlert (
        uint _customer_id,
        uint _bank_id
    );

    /**************************************************** 
     ********************* Modifiers ********************
     ****************************************************/
    
    modifier only_owner{
        require(msg.sender == regulator, 
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
     * Utility function that can be used if financial institutions did not want to create IDs themeselves
     */ 
    function get_id() private view returns(uint) {
        return uint256(keccak256(abi.encodePacked(now, block.difficulty)));
    }

    /**
     * Sets single KYC-execution cost for a customer
     * Currently settable only by the central authority (contract owner)
     */ 
    function set_KYC_cost(uint kyc_price, uint customer_id) public only_owner {
        customers[customer_id].kyc_price = kyc_price;
    }
    
    /**
     * Sets update constant. 
     * update_constant * kyc_price == maximal possible cost of a single update for this customer
     * @param new_value - new value of the update constant
     */ 
    function set_update_constant(uint new_value) public {
        update_constant = new_value;
    }

    /**
     * Creates a bank profile
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
        });
    }
    

    /**
     * Creates a customer profile for a real customer that approached a financial institution
     * Executed only by the 1st institution this customer approached
     * @param bank_id - id of bank that is in charge of the account and starts operating with the customer
     * @param account_id  - id of account the institution uses to operate with the customer
     * @param customer_id - customer's id
     * @param kyc_cost    - average cost of executing KYC for this customer
     * @param repeat_probability - probability with which the process needs to be repeated for the customer 
     * @param doc_package_hash - hash of the document package for the customer
     */ 
    function create_customer(uint bank_id, uint account_id, uint customer_id, uint kyc_cost, uint repeat_probability, bytes32 doc_package_hash) public payable {
        // require unique customer id
        require(!customers[customer_id].registered, "Customer under this id already registered. Please choose another id");
        // require each bank account to have a unique account id
        require(account_ids[account_id] == false);
        // check that given bank account not already operating with the customer
        require( check_customer_and_bank_account(customer_id, account_id, msg.sender), "This bank account is already registered with the customer" );
        // require that no fee is paid  by the 1st bank
        require(msg.value == 0, "You are the first institution to operate with the customer. No fee required.");
        // verify that the bank is registered
        require(banks[bank_id].registered == true, "Bank under specified id not registered yet.");

        // account id now assigned
        account_ids[account_id] = true;

        // create new customer
        customers[customer_id] = Customer(doc_package_hash, customer_id, true, false, false, 0, kyc_cost * 1 ether, kyc_cost * 1 ether, repeat_probability, 0, 0, 0, 0);

        // increase number of customers
        customers_length++;
        
        // increase counter 
        customers[customer_id].kyc_count++;

        // increment balance assigned to the customer
        customers[customer_id].customer_balance += msg.value;
        
        // onboard the bank account
        onboarded_list[customer_id].push(
            BankAccount(msg.sender, account_id, true)
        );

        // add customer to the list of customers the Bank is operating with
        banks[bank_id].customers[customer_id] = true;
        // this Bank has to execute KYC as it is first to operate with the customer
        banks[bank_id].kyc_executions[customer_id] = true;
        
        // store account index to be easily retrieved by account id
        account_indices[account_id] = onboarded_list[customer_id].length-1;
        
        // increment counter
        onboarded_list_length[customer_id]++;
    }

    
    /**
     * Sets customer's flag that determines whether KYC is being updated for the customer
     * @param customer_id - update is being executed for the specified customer 
     */ 
    function set_customer_update_flag(uint bank_id, uint customer_id) public {
        uint account_id = address_to_id[msg.sender];
        uint account_index = account_indices[account_id];
        
        // check update for the customer is required 
        require(customers[customer_id].require_update == true, "Customer's KYC process does not need to be updated.");
        // require that the bank account is operating with the customer 
        require(onboarded_list[customer_id][account_index].account_address==msg.sender, "This bank account is not operating with the customer");
        
        customers[customer_id].update_in_progress = true;

        // record bank that is responsible for the update
        banks[bank_id].kyc_update_flags[customer_id] = true;
    }

    
    /**
     * Sets flag that determines whether update needs to be executed for the customer
     * @param customer_id - id of the customer
     * @param flag_value - value of the flag
     */ 
    function require_customer_update(uint customer_id, bool flag_value) public only_owner{
        customers[customer_id].require_update = flag_value;
        
        // if setting to true, emit an event as a reminder to institutions operating with the customer
        if (flag_value == true) {
            emit KYCUpdateRequired(customer_id);
        }
    }


    /**
     * Updates hash of a customer's document package
     * @param bank_id - bank's id 
     * @param customer_id - customer's id 
     * @param doc_package_hash - hash of the document package 
     * @param update_cost - cost of executing this update for the customer
     */ 
    function update_KYC_doc_package(uint bank_id, uint customer_id, bytes32 doc_package_hash, uint update_cost) public {
        
        // retrieve bank's account id & index
        uint account_id = address_to_id[msg.sender];
        uint account_index = account_indices[account_id];
        
        // require that the customer's KYC process needs be updated 
        require(customers[customer_id].require_update == true, "Customer's KYC process does not need to be updated");
        // require that the update flag is set to true 
        require(customers[customer_id].update_in_progress == true, "Customer's KYC process flag was not set to true");
        // require that the update flag was set by this bank 
        require(banks[bank_id].kyc_update_flags[customer_id] == true, "This bank should not execute the KYC update for the specified customer.");
        // require that the bank account is operating with the customer 
        require(onboarded_list[customer_id][account_index].account_address == msg.sender, "This bank account is not operating with the customer");
        // require update cost is smaller than single KYC cost for the customer
        require(update_cost <= customers[customer_id].kyc_price * update_constant, "Update cost has to be lower than maximal update price");
        // require a new document package hash 
        require(customers[customer_id].document_package_hash != doc_package_hash, "Document package hash is unchanged to the existing one");
        // require bank operates with the customer 
        require(banks[bank_id].customers[customer_id] == true, "This bank does not operate with the specified customer.");

        // update the document package hash of the customer
        customers[customer_id].document_package_hash = doc_package_hash;
        
        // cost of update / # onboarded bank accounts (including the one currently getting onboarded)
        uint debt_value = update_cost / (onboarded_list[customer_id].length);
        
        // loop through onboarded bank accounts of the customer
        for (uint account_ind=0; account_ind<onboarded_list[customer_id].length; account_ind++) {
            // ensure the bank doing the update is not created a debt to itself
            if (onboarded_list[customer_id][account_ind].account_address != msg.sender) {
                // increase debt value owed to the account being currently onboarded by debt_value; all account_ind will owe to account_id
                onboarded_list[customer_id][account_ind].debts[account_id] += debt_value;
                
                // emit debt alert 
                emit DebtAlert(msg.sender, customer_id, account_id, debt_value, now);
            }
        }
        
        // update the flags
        customers[customer_id].update_in_progress    = false;
        customers[customer_id].require_update        = false;
        banks[bank_id].kyc_update_flags[customer_id] = false;

        // bank with bank_id is now a part of executing the KYC process for this customer
        banks[bank_id].kyc_executions[customer_id] = true;
    }
    
    /**
     * Assigns rating to a financial institution by another financial institution for executing KYC
     * @param bank_id_to - id of the bank being rated (Bank A)
     * @param bank_id_from - id of the bank that rates the first bank (Bank B)
     * @param customer_id - id of the customer these two institutions both operate with
     * @param rating - value of the rating assigned
     */
    function assign_bank_rating(uint bank_id_to, uint bank_id_from, uint customer_id, uint rating) public {
        // restrict rating range (1 to 10)
        require(1 <= rating && rating <= 10, "Rating needs to be between 1 to 10");

        // verify bank that assigns the rating 
        require( msg.sender == banks[bank_id_from].bank_address );

        // check that the bank being rated really executed KYC for the specified customer
        require( banks[bank_id_to].kyc_executions[customer_id] == true, "Bank cannot be rated because it did not execute KYC for this customer" );

        // verify that the bank that assigns the rating really operated with the customer whose id is specified
        require( banks[bank_id_from].customers[customer_id] == true, "You do not operate with the specified customer and therefore cannot rate another institution based on experience with this customer." );

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

        // calculate the average
        banks[bank_id_to].rating_average = banks[bank_id_to].rating_cumulative / banks[bank_id_to].rating_count;
    }

    
    /**
     * Sets rating for a customer by a financial institution 
     * @param account_id - bank's account id 
     * @param customer_id - customer's id
     * @param rating_value - value of rating (1-10) for the customer
     */ 
    function assign_customer_rating(uint account_id, uint customer_id, uint rating_value) public {
        // retrieve account index
        uint account_index = account_indices[account_id];
        
        // bank account must be operating with the customer
        require(onboarded_list[customer_id][account_index].account_address == msg.sender);
    
        // rating between 1-10
        require( 1 <= rating_value && rating_value <= 10);
        
        // assign the rating
        customers[customer_id].ratings[account_id] = rating_value;
    
        // update rating stats
        customers[customer_id].rating_cumulative += rating_value;
        customers[customer_id].rating_count++;
        customers[customer_id].rating_average = customers[customer_id].rating_cumulative / customers[customer_id].rating_count;
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
     * @param customer_id - customer's id
     * @param account_id - bank's account id
     * @param bank_id - bank's id 
     */ 
    function enter_customers_onboarded_list(uint customer_id, uint account_id, uint bank_id) public payable {
        
        // require each bank account to have a unique account id
        require(account_ids[account_id] == false);
        // check that given bank account not already operating with the customer
        require( check_customer_and_bank_account(customer_id, account_id, msg.sender), "This bank account is already registered with the customer" );
        // at least one institution already onboarded
        require(onboarded_list[customer_id].length > 0 );
        // require fee based on how many fin. inst. operate with the customer
        require(msg.value >= customers[customer_id].cumulative_kyc_cost / (onboarded_list[customer_id].length + 1), "You need to pay appropriate fee");
            
        // account id now assigned
        account_ids[account_id] = true;
            
        // increment balance assigned to the customer
        customers[customer_id].customer_balance += msg.value;

        // distribute customer's balance across other financial institutions
        distribute_contract_balance(customer_id);

        // onboard the bank account
        onboarded_list[customer_id].push(
            BankAccount(msg.sender, account_id, true)
        );
        
        // store account index to be easily retrieved by account id
        account_indices[account_id] = onboarded_list[customer_id].length-1;
        
        // increment counter
        onboarded_list_length[customer_id]++;
        
        // get random number in interval <0,100> based on customer's id and bank account id
        uint8 random_number = get_random_number(customer_id, account_id, customers[customer_id].document_package_hash);
        
        // repeat KYC
        if (random_number <= customers[customer_id].repeat_probability) {
            // increase cumulative KYC price
            customers[customer_id].cumulative_kyc_cost += customers[customer_id].kyc_price;
            
            // increase counter 
            customers[customer_id].kyc_count++;

            // this bank is now a part of executing KYC for this customer
            banks[bank_id].kyc_executions[customer_id] = true;

            // emit an event to repeat KYC
            emit RepeatKYC(account_id, customers[customer_id].document_package_hash);
            
            // price to be paid for having to repeat KYC is KYC_PRICE / # onboarded bank accounts (including the one currently getting onboarded)
            uint debt_value = customers[customer_id].kyc_price / (onboarded_list[customer_id].length);
            
            // loop through onboarded bank accounts of the customer (except for the one just added)
            for (uint account_ind=0; account_ind<onboarded_list[customer_id].length-1; account_ind++) {

                // increase debt value owed to the account being currently onboarded by debt_value; all account_ind will owe to account_id
                onboarded_list[customer_id][account_ind].debts[account_id] += debt_value;
                
                // emit debt alert 
                emit DebtAlert(msg.sender, customer_id, account_id, debt_value, now);
            }
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
     * @param debtee_address    - address of the bank's account that is owed 
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
    
    
    /**
     * Retrieves value of debt between two financial institution in reference to a customer 
     * @param debtee_account_id - bank's account id of bank that is owed 
     * @param debtor_account_id - bank's account id of bank that owes 
     * @param customer_id - customer's id 
     */ 
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
    
}