// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

contract KYC_ASSGN {

    address admin;

    enum BankActions {
        AddKYC,
        RemoveKYC,
        ApproveKYC,
        AddCustomer,
        RemoveCustomer,
        ModifyCustomer,
        DeleteCustomer,
        UpVoteCustomer,
        DownVoteCustomer,
        ViewCustomer,

        ReportSuspectedBank
    }

    struct Customer {
        string name;
        string data;
        uint256 upVotes;
        uint256 downVotes;
        address validatedBank;
        bool kycStatus;
    }

    struct Bank {
        string name;
        string regNumber;
        uint256 suspiciousVotes;
        uint256 kycCount;
        address ethAddress;
        bool isAllowedToAddCustomer;
        bool kycPrivilege;
        bool votingPrivilege;
    }

    struct Request {
        string customerName;
        string customerData;
        address bankAddress;
        bool isAllowed;
    }
    event ContractInitialized();
    event CustomerRequestAdded();
    event CustomerRequestRemoved();
    event CustomerRequestApproved();

    event NewCustomerCreated();
    event CustomerRemoved();
    event CustomerInfoModified();
    event NewBankCreated();
    event BankRemoved();
    event BankBlockedFromKYC();

    constructor() {
        emit ContractInitialized();
        admin = msg.sender;
    }


    address[] bankAddresses;  

    mapping(string => Customer) customersInfo;  
    mapping(address => Bank) banks; 
    mapping(string => Bank) bankVsRegNoMapping; 
    mapping(string => Request) kycRequests;  
    mapping(string => mapping(address => uint256)) upvotes; 
    mapping(string => mapping(address => uint256)) downvotes; 
    mapping(address => mapping(uint256 => uint256)) bankActionsAudit; 

   
   //******************************** BANK INTERFACE************************ */


    function addNewCustomerRequest(string memory custName, string memory custData) public payable returns(int){
        require(banks[msg.sender].kycPrivilege, "Requested Bank does'nt have KYC Privilege");
        require(kycRequests[custName].bankAddress != address(0), "A KYC Request is already pending with this Customer");

        kycRequests[custName] = Request(custName,custData, msg.sender, false);
        banks[msg.sender].kycCount++;
        emit CustomerRequestAdded();
        auditBankAction(msg.sender,BankActions.AddKYC);

        return 1;
    }

  

    function removeCustomerRequest(string memory custName) public payable returns(int){
        require(kycRequests[custName].bankAddress ==msg.sender, "Requested Bank is not authorized to remove this customer as KYC is not initiated by you");
        delete kycRequests[custName];
        emit CustomerRequestRemoved();
        auditBankAction(msg.sender,BankActions.RemoveKYC);
        return 1;
    }

    
    function addCustomer(string memory custName,string memory custData) public payable {
        require(banks[msg.sender].isAllowedToAddCustomer, "Requested Bank does not have Voting Privilege");
        require(customersInfo[custName].validatedBank == address(0), "Requested Customer already exists");

        customersInfo[custName] = Customer(custName, custData, 0,0,msg.sender,false);

        auditBankAction(msg.sender,BankActions.AddCustomer);

        emit NewCustomerCreated();
    }


    function removeCustomer(string memory custName) public payable returns(int){
        require(customersInfo[custName].validatedBank != address(0), "Requested Customer not found");
        require(customersInfo[custName].validatedBank ==msg.sender, "Requested Bank is not authorized to remove this customer as KYC is not initiated by you");

        delete customersInfo[custName];
        removeCustomerRequest(custName);
        auditBankAction(msg.sender,BankActions.RemoveCustomer);
        emit CustomerRemoved();
        return 1;
    }


    function modifyCustomer(string memory custName,string memory custData) public payable returns(int){
        require(customersInfo[custName].validatedBank != address(0), "Requested Customer not found");
        removeCustomerRequest(custName);

        customersInfo[custName].data = custData;
        customersInfo[custName].upVotes = 0;
        customersInfo[custName].downVotes = 0;

        auditBankAction(msg.sender,BankActions.ModifyCustomer);
        emit CustomerInfoModified();

        return 1;
    }

   

    function viewCustomerData(string memory custName) public payable returns(string memory,bool){
        require(customersInfo[custName].validatedBank != address(0), "Requested Customer not found");
        auditBankAction(msg.sender,BankActions.ViewCustomer);
        return (customersInfo[custName].data,customersInfo[custName].kycStatus);
    }

  

    function getCustomerKycStatus(string memory custName) public payable returns(bool){
        require(customersInfo[custName].validatedBank != address(0), "Requested Customer not found");
        auditBankAction(msg.sender,BankActions.ViewCustomer);
        return (customersInfo[custName].kycStatus);
    }

    

    function upVoteCustomer(string memory custName) public payable returns(int){
        require(banks[msg.sender].votingPrivilege, "Requested Bank does not have Voting Privilege");
        require(customersInfo[custName].validatedBank != address(0), "Requested Customer not found");
        customersInfo[custName].upVotes++;
        customersInfo[custName].kycStatus = (customersInfo[custName].upVotes > customersInfo[custName].downVotes && customersInfo[custName].upVotes >  bankAddresses.length/3);
        upvotes[custName][msg.sender] = block.timestamp;
        auditBankAction(msg.sender,BankActions.UpVoteCustomer);
        return 1;
    }

   
    function downVoteCustomer(string memory custName) public payable returns(int){
        require(banks[msg.sender].votingPrivilege, "Requested Bank does not have Voting Privilege");
        require(customersInfo[custName].validatedBank != address(0), "Requested Customer not found");
        customersInfo[custName].downVotes++;
        customersInfo[custName].kycStatus = (customersInfo[custName].upVotes > customersInfo[custName].downVotes && customersInfo[custName].upVotes >  bankAddresses.length/3);
        downvotes[custName][msg.sender] = block.timestamp;
        auditBankAction(msg.sender,BankActions.DownVoteCustomer);
        return 1;
    }

  
    function reportSuspectedBank(address suspiciousBankAddress) public payable returns(int){
        require(banks[suspiciousBankAddress].ethAddress != address(0), "Requested Bank not found");
        banks[suspiciousBankAddress].suspiciousVotes++;

        auditBankAction(msg.sender,BankActions.ReportSuspectedBank);
        return 1;
    }

    
    function getReportCountOfBank(address suspiciousBankAddress) public payable returns(uint256){
        require(banks[suspiciousBankAddress].ethAddress != address(0), "Requested Bank not found");
        return banks[suspiciousBankAddress].suspiciousVotes;
    }



    /***********************************   ADMIN INTERFACE  *************************************************/
    function addBank(string memory bankName,string memory regNumber,address ethAddress) public payable {

        require(msg.sender==admin, "Only admin can add bank");
        require(!areBothStringSame(banks[ethAddress].name,bankName), "A Bank already exists with same name");
        require(bankVsRegNoMapping[bankName].ethAddress != address(0), "A Bank already exists with same registration number");

        banks[ethAddress] = Bank(bankName,regNumber,0,0,ethAddress,true,true,true);
        bankAddresses.push(ethAddress);

        emit NewBankCreated();
    }

   
    function removeBank(address ethAddress) public payable returns(int){
        require(msg.sender==admin, "Only admin can remove bank");
        require(banks[ethAddress].ethAddress != address(0), "Bank not found");

        delete banks[ethAddress];

        emit BankRemoved();
        return 1;
    }

  
    function blockBankFromKYC(address ethAddress) public payable returns(int){
        require(banks[ethAddress].ethAddress != address(0), "Bank not found");
        banks[ethAddress].kycPrivilege = false;
        emit BankBlockedFromKYC();
        return 1;
    }

 
    function blockBankFromVoting(address ethAddress) public payable returns(int){
        require(banks[ethAddress].ethAddress != address(0), "Bank not found");
        banks[ethAddress].votingPrivilege = false;
        emit BankBlockedFromKYC();
        return 1;
    }


    function auditBankAction(address changesDoneBy, BankActions bankAction) private {
        bankActionsAudit[changesDoneBy][uint256(bankAction)] = (block.timestamp);
    }

  
    function areBothStringSame(string memory a, string memory b) private pure returns (bool) {
        if(bytes(a).length != bytes(b).length) {
            return false;
        } else {
            return keccak256(bytes(a)) == keccak256(bytes(b));
        }
    }
}
