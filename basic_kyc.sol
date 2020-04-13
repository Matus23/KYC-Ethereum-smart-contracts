pragma solidity >=0.4.22 <0.6.0;

/*
 * This contract simulates Basic Know-Your-Customer process that needs to be 
 * executed by financial institutions before conducting business with a customer.
 * The contract should be deployed on a private permissioned blockchain
 * @author - Matus Drgon
*/

contract KYC {
    
    /**
     * @property document_package_hash - hash of the customer's document package
     * @property registered - determines whether a customer has been rgistered by a fin. inst.
     * @property customer_balance - represents balance of each customer that is to be redistributed between the fin. inst. 
                                operating with the customer in a fair way  
     */ 
    struct Customer {
        bytes32 document_package;
        bool registered;
        uint customer_balance;
    }

    /**
     * @property account_address - public key of account the bank is using for dealing with a customer
     * @property id - unique identificator for the bank account
     * @property exists - whether this bank account is registered
     */ 
    struct BankAccount {
        address payable account_address;
        uint id;
        bool exists;
    }

    // average price of executing KYC - set by home bank
    uint public KYC_PRICE = 1 ether;

    // contract owner == regulator
    address payable private regulator;

    // each customer has a list of onboarded financial institutions operating with them
    mapping (uint => BankAccount[]) public onboarded_list;
    // length of onboarded list of a customer
    mapping (uint => uint) public onboarded_list_length;
    
    mapping (uint => Customer) public customers;
    uint public customers_length;
    
    /**
     * Constructor initialises address of the contract owner
     */ 
    constructor() public payable {
        regulator = msg.sender;
    }

    /**************************************************** 
     ********************* Modifiers ********************
     ****************************************************/
    
    modifier only_owner{
        require(msg.sender == regulator, 
                "Function callable only by the home bank (contract owner)");
        _;
    }

    /**************************************************** 
     ********************* Functions ********************
     ****************************************************/
    
    /**
     * Sets average KYC price - executable only by regulator
     * @param price - single KYC execution cost
     */
    function set_kyc_price(uint256 price) public only_owner {
        KYC_PRICE = price * 1 ether;
    }
    
    /**
     * Creates a customer's blockchain profile
     * @param id - customer's id
     */ 
    function create_customer(uint id) public {
        require(!customers[id].registered, "Customer under this id already registered. Please choose another id");
        
        // create new customer, currently doc package does not exist
        customers[id] = Customer(0x0, true, 0);

        // increase number of customers
        customers_length++;
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
     * Enters financial institution into onboarded list of the given customer
     * @param account_id - id of bank account that the bank uses to operate with the customer 
     * @param customer_id - id of customer the bank wants to operate with 
     * @param doc_package - hash of document package of the customer; if institution is not the home bank, 
     *                      can be left unset (i.e. 0x0 or arbitrary value)
     */ 
    function enter_customers_onboarded_list(uint customer_id, uint account_id, bytes32 doc_package) public payable {
        // at least one institution already onboarded
        if (onboarded_list[customer_id].length > 0 )
        {
            // require fee based on how many fin. inst. operate with the customer
            require(msg.value >= KYC_PRICE / (onboarded_list[customer_id].length + 1), "You need to pay appropriate fee");
        }
        // no institution onboarded
        else 
        {  
            require(msg.value == 0, "You are the first institution to operate with the customer. No fee required.");
            require(doc_package != 0x0, "Provided document package cannot be empty.");
            
            // initialise the document package for the customer
            customers[customer_id].document_package = doc_package;
        }

        require( check_customer_and_bank_account(customer_id, account_id, msg.sender), "This bank account is already registered with the customer" );

        // increment balance assigned to the customer
        customers[customer_id].customer_balance += msg.value;

        // distribute customer's balance across other financial institutions
        distribute_contract_balance(customer_id);

        onboarded_list[customer_id].push(
            BankAccount(msg.sender, account_id, true)
        );
        
        onboarded_list_length[customer_id]++;
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
    
}