/** 
Grim Finance POL feeRecipient. Comptroller for veNFT, Bribing, Voting & POL management.
Version 1.0

@author Nikar0 - https://www.github.com/nikar0 - https://twitter.com/Nikar0_

https://app.grim.finance - https://twitter.com/FinanceGrim
**/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IGrimVaultV2.sol";
import "./interfaces/IUniRouter.sol";
import "./interfaces/IRecipient.sol";
import "./interfaces/ISolidlyRouter.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IBribe.sol";
import "./interfaces/IVeToken.sol";
import "./interfaces/IWETH.sol";

contract GrimFeeRecipientPOL2 is Ownable {
    using SafeERC20 for IERC20;

    /** EVENTS **/
    event Buyback(uint256 indexed evoBuyBack);
    event AddPOL(uint256 indexed amount);
    event SubPOL(uint256 indexed amount);
    event PolRebalance(address indexed from, uint256 indexed amount);
    event EvoBribe(uint256 indexed amount);
    event MixedBribe(address[] indexed tokens, uint256[] indexed amounts);
    event Vote(address[] indexed poolsVoted, int256[] indexed weights);
    event CreateLock(uint256 indexed amount);
    event AddLockAmount(uint256 indexed amount);
    event AddLockTime(uint256 indexed lockTimeAdded);
    event NftIDInUse(uint256 indexed id);
    event SetUniCustomPathAndRouter(address[] indexed custompath, address indexed newRouter);
    event SetSolidlyCustomPathAndRouter(ISolidlyRouter.Routes[] indexed customPath, address indexed newRouter);
    event StuckToken(address indexed stuckToken);
    event SetTreasury(address indexed newTreasury);
    event SetStrategist(address indexed newStrategist);
    event SetBribeContract(address indexed newBribeContract);
    event SetGrimVault(address indexed newVault);
    event ExitFromContract(uint256 indexed nftId, address indexed newFeeRecipient);

    /** TOKENS **/
    address public constant wftm = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant grimEvo = address(0x0a77866C01429941BFC7854c0c0675dB1015218b);
    address public constant equal = address(0x3Fd3A0c85B70754eFc07aC9Ac0cbBDCe664865A6);
    address public constant veToken = address(0x8313f3551C4D3984FfbaDFb42f780D0c8763Ce94);
    address public constant evoLP = address(0x5462F8c029ab3461d1784cE8B6F6004f6F6E2Fd4);
    address public stableToken = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);


    /**PROTOCOL ADDRESSES **/
    address public evoVault = address(0xb2cf157bA7B44922B30732ba0E98B95913c266A4);
    address public treasury = address(0xfAE236b4E261278C2B84e74b4631cf7BCAFca06d);
    address private strategist;

    /** 3RD PARTY ADDRESSES **/
    address public bribeContract = address(0x18EB9dAdbA5EAB20b16cfC0DD90a92AF303477B1);
    address public voter = address(0x4bebEB8188aEF8287f9a7d1E4f01d76cBE060d5b);
    address public solidlyRouter = address(0x2aa07920E4ecb4ea8C801D9DFEce63875623B285);
    address public unirouter;
    
    /** PATHS **/
    address[] public ftmToGrimEvoUniPath;
    address[] public customUniPath;
    ISolidlyRouter.Routes[] public wftmToGrimEvoPath;
    ISolidlyRouter.Routes[] public equalToGrimEvoPath;
    ISolidlyRouter.Routes[] public customSolidlyPath;

    //* RECORD KEEPING **/
    uint256 public nftID;
    uint256 public lastVote;
    address[] public lastBribes;
    
    constructor ( 
        ISolidlyRouter.Routes[] memory _wftmToGrimEvoPath,
        ISolidlyRouter.Routes[] memory _equalToGrimEvoPath
    )  {

        for (uint i; i < _equalToGrimEvoPath.length; ++i) {
            equalToGrimEvoPath.push(_equalToGrimEvoPath[i]);
        }

        for (uint i; i < _wftmToGrimEvoPath.length; ++i) {
            wftmToGrimEvoPath.push(_wftmToGrimEvoPath[i]);
        }

        ftmToGrimEvoUniPath = [wftm, grimEvo];
        strategist = msg.sender;
    }

    /** SETTERS **/
    function setBribeContract(address _bribeContract) external onlyOwner {
        require(_bribeContract != bribeContract && _bribeContract != address(0), "Invalid Address");
        bribeContract = _bribeContract;
        emit SetBribeContract(_bribeContract);
    }

    function setGrimVault(address _evoVault) external onlyOwner {
        require(_evoVault != evoVault && _evoVault != address(0), "Invalid Address");
        evoVault = _evoVault;
        emit SetGrimVault(_evoVault);
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
        require(_token != stableToken && _token != address(0), "Invalid Address");
        stableToken = _token;
    }

    function setNftId(uint256 _id) external onlyAdmin {
        require(IVeToken(veToken).ownerOf(_id) == address(this), "!NFT owner");
        nftID = _id;
        emit NftIDInUse(nftID);
    }

    function setUniCustomPathsAndRouter(address[] calldata _custompath, address _router) external onlyAdmin {
        require(_router != address(0), "Invalid Address");
        if(_custompath.length > 0){
        customUniPath = _custompath;
        }
      
        if(_router != unirouter){
        unirouter = _router;
        }
        emit SetUniCustomPathAndRouter(customUniPath, unirouter);
    }

    function setSolidlyPathsAndRouter(ISolidlyRouter.Routes[] calldata _customPath, address _router) external onlyAdmin {
        require(_router != address(0), "Invalid Address");
        if (_customPath.length > 0) {
            delete customSolidlyPath;
            for (uint i; i < _customPath.length; ++i) {
                customSolidlyPath.push(_customPath[i]);}
        }
        if (_router != solidlyRouter) {
            solidlyRouter = _router;
        }
        emit SetSolidlyCustomPathAndRouter(customSolidlyPath, solidlyRouter);
    }


    /** UTILS **/
    function incaseTokensGetStuck(address _token, uint256 _amount) external onlyAdmin {
        require(_token != wftm, "Invalid token");
        require(_token != equal, "Invalid token");
        require(_token != grimEvo, "Invalid token");
        require(_token != stableToken, "Invalid token");
        require(_token != evoLP, "Invalid token");
        uint256 bal;

        if(_amount ==0){
        bal = IERC20(_token).balanceOf(address(this));
        } else { bal = _amount;}
        IERC20(_token).transfer(msg.sender, bal);
        emit StuckToken(_token);
    }

    function approvalCheck(address _spender, address _token, uint256 _amount) internal {
        if (IERC20(_token).allowance(_spender, address(this)) < _amount) {
            IERC20(_token).approve(_spender, 0);
            IERC20(_token).approve(_spender, _amount);
        }
    }

    function solidlyEvoFullBuyback() external onlyAdmin {
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        uint256 ftmBB;

        if(wftmBal > 0){
           (ftmBB,) = ISolidlyRouter(solidlyRouter).getAmountOut(wftmBal, wftm, grimEvo);
           approvalCheck(solidlyRouter, wftm, wftmBal);
           ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(wftmBal, 1, wftmToGrimEvoPath, address(this), block.timestamp);
        }

        uint256 equalBal = IERC20(equal).balanceOf(address(this));
        uint256 equalBB;
        if(equalBal > 0){
           (equalBB,) = ISolidlyRouter(solidlyRouter).getAmountOut(equalBal, equal, grimEvo);
           approvalCheck(solidlyRouter, equal, equalBal);
           ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(equalBal, 1, equalToGrimEvoPath, address(this), block.timestamp);
        }
        emit Buyback((equalBB + ftmBB));
    }

    
    function uniFtmToEvoBuyback() external onlyAdmin {
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        approvalCheck(unirouter, wftm, wftmBal);
        uint256 ftmBB = IUniRouter(unirouter).getAmountsOut(wftmBal, ftmToGrimEvoUniPath)[1];
        IUniRouter(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(wftmBal, 1, ftmToGrimEvoUniPath, address(this), block.timestamp);
        emit Buyback(ftmBB);
    }


    /** POL **/
    function polRebalance(address _tokenFrom, ISolidlyRouter.Routes[] calldata _path, uint256 _amount) external onlyAdmin{
        uint256 tokenBal;
        if(_amount == 0){
            tokenBal = IERC20(_tokenFrom).balanceOf(address(this)); } else {tokenBal = _amount;}
        approvalCheck(solidlyRouter, _tokenFrom, tokenBal);
        ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(tokenBal, 1, _path, address(this), block.timestamp);
        emit PolRebalance(_tokenFrom, tokenBal);
    }

    function addEvoPOL(uint256 _wftmAmount) external onlyAdmin {
        uint256 evoBal;
        uint256 wftmBal;
        uint256 lpBal;
       
        if(_wftmAmount == 0){
            wftmBal = IERC20(wftm).balanceOf(address(this)) / 2; } else {wftmBal = _wftmAmount / 2;}

        approvalCheck(solidlyRouter, wftm, wftmBal * 2);
        evoBal = ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSimple(wftmBal, 1, wftm, grimEvo, false, address(this), block.timestamp)[4];

        approvalCheck(solidlyRouter, grimEvo, evoBal);
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
            receiptBal = IGrimVaultV2(evoVault).balanceOf(address(this)) ;} else { receiptBal = _receipt;}

        IGrimVaultV2(evoVault).withdraw(receiptBal);
        liquidity = IERC20(evoLP).balanceOf(address(this));

        approvalCheck(solidlyRouter, evoLP, liquidity);
        ISolidlyRouter(solidlyRouter).removeLiquidity(grimEvo, wftm, false, liquidity, 1, 1, address(this), block.timestamp);
        ISolidlyRouter(solidlyRouter).removeLiquidityETHSupportingFeeOnTransferTokens(grimEvo, false, liquidity, 1, 1, address(this), block.timestamp);
        IWETH(wftm).deposit(address(this).balance);        
        emit SubPOL(liquidity);
    }

    function addOrRemoveCustomPOL(address[2] calldata _tokens, ISolidlyRouter.Routes[] calldata _path, address _vault, bool _stable, bool addOrRemove) external onlyAdmin{
        uint256 t1Bal = IERC20(_tokens[0]).balanceOf(address(this)) / 2;
        uint256 t2Bal;
        uint256 lpBal;
        address lp = ISolidlyRouter(solidlyRouter).pairFor(_tokens[0], _tokens[1], _stable);
        uint256 receiptBal;
        if(addOrRemove){
            approvalCheck(solidlyRouter, _tokens[0], t1Bal * 2);
            ISolidlyRouter(solidlyRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(t1Bal, 1, _path, address(this), block.timestamp);
            t2Bal = IERC20(_tokens[1]).balanceOf(address(this));

            approvalCheck(solidlyRouter, _tokens[1], t2Bal);
            ISolidlyRouter(solidlyRouter).addLiquidity(_tokens[0], _tokens[1], _stable, t1Bal, t2Bal, 1, 1, address(this), block.timestamp);
            lpBal = IERC20(lp).balanceOf(address(this));

            approvalCheck(_vault, lp, lpBal);
            IGrimVaultV2(_vault).depositAll();
        } else{
           receiptBal = IGrimVaultV2(_vault).balanceOf(address(this));
           IGrimVaultV2(_vault).withdrawAll();
           lpBal = IERC20(lp).balanceOf(address(this));

           approvalCheck(solidlyRouter, lp, lpBal);
           ISolidlyRouter(solidlyRouter).removeLiquidity(_tokens[0], _tokens[1], _stable, lpBal, 1, 1, address(this), block.timestamp);
        }

    }

    /** veNFT **/
    function createLock(uint256 _amount, uint256 _duration) external onlyAdmin {
        uint256 lockBal;
        if(_amount == 0){
            lockBal = IERC20(equal).balanceOf(address(this)); } else { lockBal = _amount;}

        approvalCheck(veToken, equal, lockBal);
        nftID = IVeToken(veToken).create_lock(lockBal, _duration);
        emit CreateLock(lockBal);
    }

    function addLockAmount(uint256 _amount) external onlyAdmin {
        uint256 lockBal;
        if(_amount == 0){
            lockBal = IERC20(equal).balanceOf(address(this)); } else { lockBal = _amount;

        approvalCheck(veToken, equal, lockBal);
        IVeToken(veToken).increase_amount(nftID, lockBal);
        emit AddLockAmount(lockBal);}  
    }

    function addLockDuration(uint256 _timeAdded) external onlyAdmin {
        IVeToken(veToken).increase_unlock_time(nftID, _timeAdded);
        emit AddLockTime(_timeAdded);
    }

    function vote(address[] calldata _pools, int256[] calldata _weights) external onlyAdmin {
        lastBribes = _pools;
        IVoter(voter).vote(nftID, _pools, _weights);
        lastVote = block.timestamp;
        emit Vote(_pools, _weights);
    }

    function unlockNFT() external onlyOwner {
        IVeToken(veToken).withdraw(nftID);
    }

    function claimRewards(address[][] calldata _tokens) external onlyAdmin {
        IVoter(voter).claimBribes(lastBribes, _tokens, nftID);
    }


    /** BRIBING **/
    function evoBribe(uint256 _amount) external onlyAdmin{
        uint256 evoBal;
        if(_amount == 0){
           evoBal = IERC20(grimEvo).balanceOf(address(this));} else {evoBal = _amount;}
        
        approvalCheck(bribeContract, grimEvo, evoBal);
        IBribe(bribeContract).notifyRewardAmount(grimEvo, evoBal);
        emit EvoBribe(evoBal);
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
        t0Bal = IERC20(_tokens[0]).balanceOf(address(this));} else {t0Bal = _tokenAmounts[0];}
        if(_tokenAmounts[1] == 0){
        t1Bal = IERC20(_tokens[1]).balanceOf(address(this));} else {t1Bal = _tokenAmounts[1];}
        
        if(_tokens[2] != address(0)){
            if(_tokenAmounts[2] == 0){
            t2Bal = IERC20(_tokens[2]).balanceOf(address(this));} else {t2Bal = _tokenAmounts[2];}
        } 

        approvalCheck(bribeContract, _tokens[0], t0Bal);
        approvalCheck(bribeContract, _tokens[1], t1Bal);

        IBribe(bribeContract).notifyRewardAmount(_tokens[0], t0Bal);
        IBribe(bribeContract).notifyRewardAmount(_tokens[1], t1Bal);
        if(t2Bal > 0){
            approvalCheck(bribeContract, _tokens[2], t2Bal);
            IBribe(bribeContract).notifyRewardAmount(_tokens[2], t2Bal);
        }
        emit MixedBribe(_tokens, _tokenAmounts);
    }


    /** MIGRATION **/
    function exitFromContract(address _receiver) external onlyOwner {
        require(_receiver != address(0), "Invalid toAddress");
        require(_receiver == treasury || IRecipient(_receiver).oldRecipient() == address(this), "Invalid toAddress");
        IVeToken(veToken).reset();
        uint256 equalBal = IERC20(equal).balanceOf(address(this));
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        uint256 evoBal = IERC20(grimEvo).balanceOf(address(this));
        uint256 stableBal = IERC20(stableToken).balanceOf(address(this));
        uint256 receiptBal = IGrimVaultV2(evoVault).balanceOf(address(this));
        uint256 lpBal = IERC20(evoLP).balanceOf(address(this));

        IERC721(veToken).approve(msg.sender, nftID);
        IERC721(veToken).approve(_receiver, nftID);
        IERC721(veToken).safeTransferFrom(address(this), _receiver, nftID);

        if(receiptBal > 0){
            subEvoPOL(receiptBal);
            lpBal = IERC20(evoLP).balanceOf(address(this));
            IERC20(evoLP).safeTransfer(_receiver, lpBal);
        }
        if(equalBal > 0){
        IERC20(equal).safeTransfer(_receiver, equalBal);
        }
        if(wftmBal > 0){
        IERC20(wftm).safeTransfer(_receiver, wftmBal);
        }
        if(evoBal > 0){
        IERC20(grimEvo).safeTransfer(_receiver, evoBal);
        }
        if(stableBal > 0){
        IERC20(stableToken).safeTransfer(_receiver, stableBal);
        }
        if(lpBal > 0){
        IERC20(evoLP).safeTransfer(_receiver, lpBal);
        }
        emit ExitFromContract(nftID, _receiver);
    }


    /** VIEWS **/
    function tokenBalances() external view returns(uint256 _grimEvo, uint256 _wftm, uint256 _equal, uint256 _stableToken, uint256 _receipt, uint256 _evoLP){
        uint256 receiptBal = IGrimVaultV2(evoVault).balanceOf(address(this));
        uint256 lpBal = IERC20(evoLP).balanceOf(address(this));
        uint256 evoBal = IERC20(grimEvo).balanceOf(address(this));
        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
        uint256 equalBal = IERC20(equal).balanceOf(address(this));
        uint256 stableBal = IERC20(stableToken).balanceOf(address(this));
        return (evoBal, wftmBal, equalBal, stableBal, receiptBal, lpBal);
    }

    function claimableRewards(address[] calldata _tokens) external view returns (address[] memory, uint256[] memory) {
       address[] memory tokenAddresses = new address[](_tokens.length);
       uint256[] memory tokenRewards = new uint256[](_tokens.length);
       uint256 earned; 
        
        for (uint i = 0; i < _tokens.length; i++) {
            earned = IBribe(bribeContract).earned(_tokens[i], nftID);
            tokenAddresses[i] = _tokens[i];
            tokenRewards[i] = earned;
        }
        return (tokenAddresses, tokenRewards);
    }


   /** ACCESS CONTROL **/
    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == strategist);
        _;
    }

    // Receive native from tax supported remove liquidity
    receive() external payable{
        require(msg.sender == solidlyRouter || msg.sender == strategist || msg.sender == owner(), "Invalid Sender");
    }

}
