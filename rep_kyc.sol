pragma solidity >=0.4.22 <0.6.0;

/*
 * This contract simulates the Know-Your-Customer process that needs to be 
 * executed by financial institutions before conducting business with a customer
 * It uses Ethereum blockchain in order to decrease the financial costs associated with process.
 * It assumes blockchain it is implemented on is private and is only accessible by the regulator
*/

contract KYC {
    
    /**
     * @property document_package_hash - hash of the customer's document package
     */ 
    struct Customer {
        bytes32 document_package;
        bool registered;
        uint customer_balance;
        uint cumulative_kyc_cost;
    }

    /**
     * Bank's account to operate with a customer. A bank uses a unique account for dealing with each customer
     * @property account_address - public key of an account the bank is using for dealing with a customer
     * @property id - unique identificator for this bank account
     * @property debts - mapping from bank account ids (ids of back accounts this account is owing to) to the debts' values
     */ 
    struct BankAccount {
        address payable account_address;
        uint id;
        bool exists;
        mapping (uint => uint) debts;
    }

    /**
     * @property name - name of the bank
     * @property id - unique identificator for the bank
     */
    struct Bank {
        string name;
        uint id;
    }

    // average price of executing KYC - set by home bank
    uint public KYC_PRICE = 1 ether;

    // probability (in %) that KYC needs to be repeated, by default 10%
    uint8 public kyc_threshold = 10; 

    // contract owner == home_bank
    address payable private home_bank;

    // (customer_id => BankAccount[]) each customer has an array of bank accounts they are operating with  
    mapping (uint => BankAccount[]) public onboarded_list;
    // length of onboarded list of a customer
    mapping (uint => uint) public onboarded_list_length;

    mapping (uint => Customer) public customers;
    uint public customers_length;

    uint public example_debt;

    /**
     * Constructor initialises address of the contract owner
     */ 
    constructor() public payable {
        home_bank = msg.sender;
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
        require(msg.sender == home_bank, 
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
     */
    function get_random_number(uint customer_id, uint account_id, bytes32 doc_package) private view returns (uint8) {
       return uint8(uint256(keccak256(abi.encodePacked(now, block.difficulty, customer_id, account_id, doc_package)))%101);
    }

    /**
     * Generates a random number serving as id for the bank
     */ 
    function get_id() private view returns(uint) {
        return uint256(keccak256(abi.encodePacked(now, block.difficulty)));
    }


    /**
     * Sets probability with which KYC will have to be repeated - executable only by regulator
     * @param threshold - threshold in %; this is due to the lack of non-integer values
     */
    function set_kyc_threshold(uint8 threshold) public only_owner {
        kyc_threshold = threshold;
    }    

    /**
     *  Sets average KYC price - executable only by home bank
     */
    function set_kyc_price(uint256 price) public only_owner {
        KYC_PRICE = price * 1 ether;
    }
    
    /**
     * Creates a customer
     * @param id - customer's id
     */ 
    function create_customer(uint id) public {
        require(!customers[id].registered, "Customer under this id already registered. Please choose another id");
        
        // create new customer
        customers[id] = Customer(0x000000000000000000000000000000, true, 0, KYC_PRICE);

        // increase number of customers
        customers_length++;
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
     */ 
    function enter_customers_onboarded_list(uint customer_id, uint account_id, bytes32 doc_package) public payable {
        // at least one institution already onboarded
        if (onboarded_list[customer_id].length > 0 )
        {
            // require fee based on how many fin. inst. operate with the customer
            require(msg.value >= customers[customer_id].cumulative_kyc_cost / (onboarded_list[customer_id].length + 1), "You need to pay appropriate fee");
            
            // increment balance assigned to the customer
            customers[customer_id].customer_balance += msg.value;
    
            // distribute customer's balance across other financial institutions
            distribute_contract_balance(customer_id);
    
            // onboard the bank account
            onboarded_list[customer_id].push(
                BankAccount(msg.sender, account_id, true)
            );
            //uint account_index = onboarded_list[customer_id].length-1;
            
            // increment counter
            onboarded_list_length[customer_id]++;
            
            // get random number in interval <0,100> based on customer's id and bank account id
            uint8 random_number = get_random_number(customer_id, account_id, customers[customer_id].document_package);
            
            // repeat KYC
            if (random_number <= kyc_threshold) {
                // increase cumulative KYC price
                customers[customer_id].cumulative_kyc_cost += KYC_PRICE;
                
                // price to be paid for having to repeat KYC is KYC_PRICE / # onboarded bank accounts (including the one currently getting onboarded)
                uint debt_value = KYC_PRICE / (onboarded_list[customer_id].length);
    
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
            
            require( check_customer_and_bank_account(customer_id, account_id, msg.sender), "This bank account is already registered with the customer" );

            // increment balance assigned to the customer
            customers[customer_id].customer_balance += msg.value;
    
            // distribute customer's balance across other financial institutions
            distribute_contract_balance(customer_id);

            // onboard the bank account
            onboarded_list[customer_id].push(
                BankAccount(msg.sender, account_id, true)
            );
            
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
    
    /**
     * Helper function to check whether contract works as expected
     * Will be deleted for final implementation
     */ 
    function get_debt_value(uint debtee_account_id, uint debtor_account_id, uint customer_id) public {
        for (uint account_ind=0; account_ind < onboarded_list[customer_id].length; account_ind++) {
            // account found
            if ( onboarded_list[customer_id][account_ind].id == debtor_account_id ) 
            {
                example_debt = onboarded_list[customer_id][account_ind].debts[debtee_account_id];
            }
        }
    }
    
}