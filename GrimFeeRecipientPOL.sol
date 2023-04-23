/** 
Grim Finance POL feeRecipient. Comptroller for veNFT, Bribing, Voting & POL management.
Version 1.0

@author Nikar0 - https://www.github.com/nikar0 - https://twitter.com/Nikar0_

https://app.grim.finance - https://twitter.com/FinanceGrim
**/

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IGrimVaultV2.sol";
import "./interfaces/IUniRouter.sol";
import "./interfaces/ISolidlyRouter.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IBribe.sol";
import "./interfaces/IVeDist.sol";
import "./interfaces/IVeToken.sol";
import "./interfaces/IGauge.sol";

contract GrimFeeRecipientPOL is Ownable {
    using SafeERC20 for IERC20;

    //Events//
    event Buyback(uint256 indexed evoBuyBack);
    event AddPOL(uint256 indexed amount);
    event SubPOL(uint256 indexed amount);
    event PolRebalance(address indexed from, address indexed to, uint256 indexed amount);
    event EvoBribe(address indexed token, uint256 indexed amount, uint256 indexed timestamp);
    event MixedBribe(address[] indexed tokens, uint256[] indexed amounts, uint256 indexed timestamp);
    event Vote(address[] indexed poolsVoted, int256[] indexed weights, uint256 indexed timestamp);
    event CreateLock(uint256 indexed amount, uint256 indexed timestamp);
    event IncreaseLockAmount(uint256 indexed amount, uint256 indexed timestamp);
    event ExtendLock(uint256 indexed lockTimeAdded, uint256 indexed timestamp);
    event TokenRebalance(address indexed from, address indexed to, uint256 amount);
    event SetCustomUniPath(address[] indexed path);
    event SetCustomSolidlyPath(ISolidlyRouter.Routes[] indexed path);
    event StuckToken(address indexed stuckToken);
    event SetTreasury(address indexed newTreasury);
    event SetStrategist(address indexed newStrategist);
    event SetUnirouter(address indexed newUnirouter);
    event SetBribeContract(address indexed newBribeContract);
    event SetGrimVault(address indexed newVault);
    event SetSolidlyRouter(address indexed newSolidlyRouter);
    event SetGauge(address indexed newGauge);
    event SetStableToken(address indexed newStableToken);
    event ExitToTreasury(uint256 indexed veNFTId, address indexed newTreasury);
    event ExitToNewRecipient(uint256 indexed nftId, address indexed newFeeRecipient);

    //Tokens//
    address public constant wftm = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant grimEvo = address(0x0a77866C01429941BFC7854c0c0675dB1015218b);
    address public constant equal = address(0x3Fd3A0c85B70754eFc07aC9Ac0cbBDCe664865A6);
    address public stableToken = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);


    //Protocol Addresses//
    address public evoVault = address(0xb2cf157bA7B44922B30732ba0E98B95913c266A4);
    address public treasury = address(0xfAE236b4E261278C2B84e74b4631cf7BCAFca06d);
    address public strategist;

    //3rd party Addresses//
    address public evoGauge = address(0x615C5795341AaABA1DE2E416096AF9bF0748Ea36);
    address public bribeContract = address(0x18EB9dAdbA5EAB20b16cfC0DD90a92AF303477B1);
    address public evoLP = address(0x5462F8c029ab3461d1784cE8B6F6004f6F6E2Fd4);
    address public veToken = address(0x8313f3551C4D3984FfbaDFb42f780D0c8763Ce94);
    address public voter = address(0x4bebEB8188aEF8287f9a7d1E4f01d76cBE060d5b);
    address public solidlyRouter = address(0x1A05EB736873485655F29a37DEf8a0AA87F5a447);
    address public unirouter;
    
    //Paths//
    address[] public ftmToGrimEvoUniPath;
    address[] public customUniPath;
    ISolidlyRouter.Routes[] public equalToGrimEvoPath;
    ISolidlyRouter.Routes[] public customSolidlyPath;

    //Record keeping//
    uint256 public lastVote;
    uint256 public lastBribe;
    

    constructor ( 
        ISolidlyRouter.Routes[] memory _equalToGrimEvoPath
    )  {

        for (uint i; i < _equalToGrimEvoPath.length; ++i) {
            equalToGrimEvoPath.push(_equalToGrimEvoPath[i]);
        }

        ftmToGrimEvoUniPath = [wftm, grimEvo];
        strategist = msg.sender;
    }

    //Setters//
    function setSolidlyRouter(address _router) external onlyAdmin {
        require(_router != solidlyRouter && _router != address(0), "Invalid Address");
        solidlyRouter = _router;
        emit SetSolidlyRouter(_router);
    }

    function setGauge(address _gauge) external onlyOwner {
        require(_gauge != evoGauge && _gauge != address(0), "Invalid Address");
        evoGauge = _gauge;
        emit SetGauge(_gauge);
    }

    function setBribeContract(address _bribeContract) external onlyOwner {
        require(_bribeContract != bribeContract && _bribeContract != address(0), "Invalid Address");
        bribeContract = _bribeContract;
        emit SetBribeContract(_bribeContract);
    }

    function setGrimVault(address _vault) external onlyOwner {
        require(_vault != evoVault && _vault != address(0), "Invalid Address");
        evoVault = _vault;
        emit SetGrimVault(_vault);
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!auth");
        strategist = _strategist;
        emit SetStrategist(_strategist);
    }

    function setTreasury(address _treasury) external onlyOwner{
        require(_treasury != treasury && _treasury != address(0), "Invalid Address");
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    function setStableToken(address _token) external onlyAdmin{
        stableToken = _token;
        emit SetStableToken(_token);
    }

    function setCustomUniPath(address[] calldata _path) external onlyOwner {
        customUniPath = _path;
        emit SetCustomUniPath(_path);
    }

    function setCustomSolidlyPath(ISolidlyRouter.Routes[] calldata _path) external onlyOwner {
        delete customSolidlyPath;

        for (uint i; i < _path.length; ++i) {
        customSolidlyPath.push(_path[i]);
        }
        emit SetCustomSolidlyPath(_path);
    }

    
    //Utils//
    function incaseTokensGetStuck(address _token) external onlyAdmin {
        require(_token != wftm, "Invalid token");
        require(_token != equal, "Invalid token");
        require(_token != grimEvo, "Invalid token");
        require(_token != stableToken, "Invalid token");

        uint256 bal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, bal);
        emit StuckToken(_token);
    }

    function approvalCheck(address _spender, address _token, uint256 _amount) internal {
        if (IERC20(_token).allowance(_spender, address(this)) < _amount) {
            IERC20(_token).approve(_spender, 0);
            IERC20(_token).approve(_spender, _amount);
        }
    }

    function solidlyEvoFullBuyback() internal {
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        approvalCheck(solidlyRouter, wftm, wftmBal);
        uint256 ftmBB = ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSimple(wftmBal, 0, wftm, grimEvo, false, address(this), block.timestamp)[4];

        uint256 equalBal = IERC20(equal).balanceOf(address(this));
        approvalCheck(solidlyRouter, equal, equalBal);
        uint256 equalBB = ISolidlyRouter(solidlyRouter).swapExactTokensForTokens(equalBal, 0, equalToGrimEvoPath, address(this), block.timestamp)[4];

        emit Buyback((equalBB + ftmBB));
    }

    function solidlyFtmToEvoBuyback() public onlyAdmin {
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        approvalCheck(solidlyRouter, wftm, wftmBal);
        uint256 ftmBB = ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSimple(wftmBal, 0, wftm, grimEvo, false, address(this), block.timestamp)[4];
        emit Buyback(ftmBB);
    }

    function uniFtmToEvoBuyback() public onlyAdmin {
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        approvalCheck(unirouter, wftm, wftmBal);
        uint256 ftmBB = IUniRouter(unirouter).getAmountsOut(wftmBal, ftmToGrimEvoUniPath)[1];
        IUniRouter(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(wftmBal, 1, ftmToGrimEvoUniPath, address(this), block.timestamp);
        emit Buyback(ftmBB);
    }


    //POL//
    function polRebalance(address _tokenFrom, address _tokenTo, uint256 _amount) external onlyAdmin{
        if(_amount == 0){
            uint256 tokenBal = IERC20(_tokenFrom).balanceOf(address(this));
            approvalCheck(solidlyRouter, _tokenFrom, tokenBal);
            ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSimple(tokenBal, 0, _tokenFrom, _tokenTo, false, address(this), block.timestamp);
            emit PolRebalance(_tokenFrom, _tokenTo, tokenBal);
        } else {
            approvalCheck(solidlyRouter, _tokenFrom, _amount);
            ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSimple(_amount, 0, _tokenFrom, _tokenTo, false, address(this), block.timestamp);
            emit PolRebalance(_tokenFrom, _tokenTo, _amount);
        }
    }

    function swapClaimable(address _tokenFrom, ISolidlyRouter.Routes[] calldata _path, uint256 _amount) external onlyAdmin{
        uint256 tokenBal;
        if(_amount == 0){
            tokenBal = IERC20(_tokenFrom).balanceOf(address(this));
        } else tokenBal = _amount;

        approvalCheck(solidlyRouter, _tokenFrom, tokenBal);
        ISolidlyRouter(solidlyRouter).swapExactTokensForTokens(tokenBal, 0, _path, address(this), block.timestamp);
    }

    function addEvoPOL(uint256 _evoAmount, uint256 _wftmAmount) external onlyAdmin {
        uint256 evoBal;
        uint256 wftmBal;
        uint256 lpBal;
        if(_evoAmount == 0){
            evoBal = IERC20(grimEvo).balanceOf(address(this));
        } else evoBal = _evoAmount;
        if(_wftmAmount == 0){
            wftmBal = IERC20(wftm).balanceOf(address(this));
        } else wftmBal = _wftmAmount;

        approvalCheck(solidlyRouter, grimEvo, evoBal);
        approvalCheck(solidlyRouter, wftm, wftmBal);
        ISolidlyRouter(solidlyRouter).addLiquidity(grimEvo, wftm, false, evoBal, wftmBal, 1, 1, address(this), block.timestamp);

        lpBal = IERC20(evoLP).balanceOf(address(this));
        approvalCheck(evoVault, evoLP, lpBal);
        IGrimVaultV2(evoVault).depositAll();
        emit AddPOL(lpBal);
    }

    function subEvoPOL(uint256 _receipt) public onlyAdmin {
        uint256 receiptBal;
        uint256 liquidity;
        if(_receipt == 0){
            receiptBal = IGrimVaultV2(evoVault).balanceOf(address(this));
        } else receiptBal = _receipt;

        IGrimVaultV2(evoVault).withdraw(receiptBal);
        liquidity = IERC20(evoLP).balanceOf(address(this));
        ISolidlyRouter(solidlyRouter).removeLiquidity(grimEvo, wftm, false, liquidity, 1, 1, address(this), block.timestamp);
        emit SubPOL(liquidity);
    }

    //veNFT//
    function createLock(uint256 _amount, uint256 _duration) external onlyAdmin {
        if(_amount == 0){
            uint256 lockBal = IERC20(equal).balanceOf(address(this));
            IVeToken(veToken).create_lock(lockBal, _duration);
            emit CreateLock(lockBal, block.timestamp);
        } else {
            IVeToken(veToken).create_lock(_amount, _duration);
            emit CreateLock(_amount, block.timestamp);
        }
    }

    function addToLockAmount(uint256 _amount) external onlyAdmin {
        if(_amount == 0){
            uint256 lockBal = IERC20(equal).balanceOf(address(this));
            IVeToken(veToken).increase_amount(0, lockBal);
            emit IncreaseLockAmount(_amount, block.timestamp);
        } else {
            IVeToken(veToken).increase_amount(0, _amount);
            emit IncreaseLockAmount(_amount, block.timestamp);}  
    }

    function addToLockDuration(uint256 _timeAdded) external onlyAdmin {
        IVeToken(veToken).increase_unlock_time(0, _timeAdded);
        emit ExtendLock(_timeAdded, block.timestamp);
    }

    function vote(address[] memory _pools, int256[] memory _weights) external onlyAdmin {
        IVoter(voter).vote(0, _pools, _weights);
        lastVote = block.timestamp;
        emit Vote(_pools, _weights, block.timestamp);
    }

    function releaseNFT(uint256 _veNftId) external onlyOwner {
        IVeToken(veToken).withdraw(_veNftId);
    }


    //Bribing
    function evoBribe(uint256 _amount) external onlyAdmin{
        require(_amount <= IERC20(grimEvo).balanceOf(address(this)), "Invalid Evo Amount");
        solidlyEvoFullBuyback();
        uint256 evoBal;
        if(_amount == 0){
           evoBal = IERC20(grimEvo).balanceOf(address(this));
           approvalCheck(bribeContract, grimEvo, evoBal);
        } else { evoBal = _amount;
           approvalCheck(bribeContract, grimEvo, evoBal);
        }

        IBribe(bribeContract).notifyRewardAmount(grimEvo, evoBal);
        lastBribe = block.timestamp;
        emit EvoBribe(grimEvo, evoBal, block.timestamp);
    }

    function mixedBribe(address[] calldata _tokens, uint256[] calldata _tokenAmounts) external onlyAdmin{
        require(_tokens.length <= 3, "over bounds");
        require(_tokenAmounts[0] <= IERC20(_tokens[0]).balanceOf(address(this)), "t0 invalid amount");
        require(_tokenAmounts[1] <= IERC20(_tokens[1]).balanceOf(address(this)), "t1 invalid amount");
        require(_tokenAmounts[2] <= IERC20(_tokens[2]).balanceOf(address(this)), "t2 invalid amount");
        uint256 t0Bal;
        uint256 t1Bal;
        uint256 t2Bal;

        if(_tokenAmounts[0] == 0){
        t0Bal = IERC20(_tokens[0]).balanceOf(address(this));
        } else t0Bal = _tokenAmounts[0];
        if(_tokenAmounts[1] == 0){
        t1Bal = IERC20(_tokens[1]).balanceOf(address(this));
        } else t1Bal = _tokenAmounts[1];
        
        if(_tokens[2] != address(0)){
            if(_tokenAmounts[2] == 0){}
            t2Bal = IERC20(_tokens[2]).balanceOf(address(this));
            approvalCheck(bribeContract, _tokens[2], t2Bal);
        } else { t2Bal = _tokenAmounts[2]; approvalCheck(bribeContract, _tokens[2], t2Bal);}

        approvalCheck(bribeContract, _tokens[0], t0Bal);
        approvalCheck(bribeContract, _tokens[1], t1Bal);

        IBribe(bribeContract).notifyRewardAmount(_tokens[0], t0Bal);
        IBribe(bribeContract).notifyRewardAmount(_tokens[1], t1Bal);
        if(t2Bal > 0){
            IBribe(bribeContract).notifyRewardAmount(_tokens[2], t2Bal);
        }
        lastBribe = block.timestamp;
        emit MixedBribe(_tokens, _tokenAmounts, block.timestamp);
    }


    //Migration
    function exitToTreasury(uint256 _id) external onlyOwner {
        uint256 equalBal = IERC20(equal).balanceOf(address(this));
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        uint256 evoBal = IERC20(grimEvo).balanceOf(address(this));
        uint256 stableBal = IERC20(stableToken).balanceOf(address(this));
        uint256 receiptBal = IGrimVaultV2(evoVault).balanceOf(address(this));
        uint256 lpBal = IERC20(evoLP).balanceOf(address(this));

        IERC721(veToken).safeTransferFrom(address(this), treasury, _id);

        if(receiptBal > 0){
            subEvoPOL(receiptBal);
            lpBal = IERC20(evoLP).balanceOf(address(this));
            IERC20(evoLP).safeTransferFrom(address(this), treasury, lpBal);
        }
        if(equalBal > 0){
        IERC20(equal).safeTransferFrom(address(this), treasury, equalBal);
        }
        if(wftmBal > 0){
        IERC20(wftm).safeTransferFrom(address(this), treasury, wftmBal);
        }
        if(evoBal > 0){
        IERC20(grimEvo).safeTransferFrom(address(this), treasury, evoBal);
        }
        if(stableBal > 0){
        IERC20(stableToken).safeTransferFrom(address(this), treasury, stableBal);
        }
        if(lpBal > 0){
        IERC20(evoLP).safeTransferFrom(address(this), treasury, lpBal);
        }
        emit ExitToTreasury(_id, treasury);
    }

    function exitToNewRecipient(uint256 _id, address _newRecipient) external onlyOwner {
        IERC721(veToken).approve(_newRecipient, _id);
        uint256 equalBal = IERC20(equal).balanceOf(address(this));
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        uint256 evoBal = IERC20(grimEvo).balanceOf(address(this));
        uint256 stableBal = IERC20(stableToken).balanceOf(address(this));
        uint256 receiptBal = IGrimVaultV2(evoVault).balanceOf(address(this));
        uint256 lpBal = IERC20(evoLP).balanceOf(address(this));

        IERC721(veToken).safeTransferFrom(address(this), _newRecipient, _id);

        if(receiptBal > 0){
            subEvoPOL(receiptBal);
            lpBal = IERC20(evoLP).balanceOf(address(this));
            IERC20(evoLP).safeTransferFrom(address(this), _newRecipient, lpBal);
        }
        if(equalBal > 0){
        approvalCheck(_newRecipient, equal, equalBal);
        IERC20(equal).safeTransferFrom(address(this), _newRecipient, equalBal);
        }
        if(wftmBal > 0){
        approvalCheck(_newRecipient, wftm, wftmBal);
        IERC20(wftm).safeTransferFrom(address(this), _newRecipient, wftmBal);
        }
        if(evoBal > 0){
        approvalCheck(_newRecipient, grimEvo, evoBal);
        IERC20(grimEvo).safeTransferFrom(address(this), _newRecipient, evoBal);
        }
        if(stableBal > 0){
        approvalCheck(_newRecipient, stableToken, stableBal);
        IERC20(stableToken).safeTransferFrom(address(this), _newRecipient, stableBal);
        }
        if(lpBal > 0){
        approvalCheck(_newRecipient, evoLP, lpBal);
        IERC20(evoLP).safeTransferFrom(address(this), _newRecipient, lpBal);
        }
        emit ExitToNewRecipient(_id, _newRecipient);
    }


    //Views//
    function tokenBalances() external view returns(uint256 _grimEvo, uint256 _wftm, uint256 _equal, uint256 _stableToken, uint256 _receipt, uint256 _evoLP){
        uint256 receiptBal = IGrimVaultV2(evoVault).balanceOf(address(this));
        uint256 lpBal = IERC20(evoLP).balanceOf(address(this));
        uint256 evoBal = IERC20(grimEvo).balanceOf(address(this));
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        uint256 equalBal = IERC20(equal).balanceOf(address(this));
        uint256 stableBal = IERC20(stableToken).balanceOf(address(this));
        return (evoBal, wftmBal, equalBal, stableBal, receiptBal, lpBal);
    }


   //Access control//
    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == strategist);
        _;
    }
}
