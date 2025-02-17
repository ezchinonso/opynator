pragma solidity ^0.6.0;

import {Controller} from "../interfaces/IController.sol";
import {IUniswapv2Router01} from "../interfaces/IuniswapV2Router.sol";
import "../interfaces/OtokenInterface.sol";
import "../interfaces/IERC20.sol";
import {SafeMath} from "../libs/SafeMath.sol";
import {PriceOracle} from "../oracle/Oracle.sol"

contract opynator {
    using SafeMath for uint256;

    Controller public controller = Controller(0x4ccc2339F87F6c59c6893E1A678c2266cA58dC72);
    IUniswapv2Router01 router = IUniswapv2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant USDC = '0x27415c30d8c87437BeCbd4f98474f26E712047f4';

    PriceOracle public oracle;

    
    mapping(address => position[]) positions;

    struct Position {
        uint itm;
        address user;
        uint userBalance;
        bool exercised;
    }
  

    function delegate(address asset) external {
        require(!controller.isOperator(msg.sender, address(this)));
        controller.setOperator(address(this), true);
    }

    function delegatePosition(address asset, uint256 amount, uint _itm) external {
        OtokenInterface otoken = OtokenInterface(asset);
        (,,,,, bool isPut) = otoken.getOtokenDetails();
        require(isPut);
        IERC20(asset).approve(address(this), amount);
        bool success = IERC20(asset).transferFrom(msg.sender, address(this), amount);
        require(success);
        
        positions[asset].push({
            itm: _itm,
            user: msg.sender,
            userBalance: amount,
            exercised: false
        });

    }

    function redeemPutBuyEthPerExp(address asset, uint deadline) external {
        
        require(controller.hasExpired(asset));
        (,address underlyingAsset,,uint256 strikePrice,,) = otoken.getOtokenDetails();
        uint underlyingAssetPrice = oracle.getLatestPrice();
        bool itm = strikePrice > underlyingAssetPrice;
        require(itm, 'OPTION_NOT_IN_THE_MONEY');
        
        uint itmness = calculateITM(underlyingAssetPrice, strikePrice);
        uint balance = 0;

        for(uint i = 0; i < positions[asset].length; i++ ){
            if(positions[asset][i].itm == 0 || positions[asset][i].itm == itmness || positions[asset][i].itm < itmness ){
                positions[asset][i].exercised = true;
            }
            if(positions[asset][i].exercised){
                balance += positions[asset][i].userBalance;
            }
        };

        ActionArg args = parseRedeemArgs(asset, address(this), balance);
        uint256 potentialPayOut = controller.getPayout(asset, balance);
        controller.operate(args);

        // @todo implement swap and get min amount of eth swapped to(x)
        // used fixed point math to calculate payout
        uint amountOutMin;
        _swap(potentialPayOut, amountOutMin ,deadline);

        for(uint i = 0; i < positions[asset].length; i++ ){
            if(positions[asset][i].exercised){
                // 😥 shity math        50IQ brain
                //             :handshake:         
                uint percentage = ((positions[asset][i].userBalance).div(balance)).mul(100);
                uint share = (x.mul(percentage)).div(100);
                (bool success, ) = positions[asset][i].user.call{value: share}();
            }
        };

    }
    function calculateITM(uint256 underlyingAssetPrice, uint256 strikePrice) view returns(uint){
        uint256 intrinsic = strikePrice.sub(underlyingAssetPrice);
        uint res = intrinsic.div(underlyingAsssetPrice);
        return res.mul(100)
    }

    function _swap(uint amount, uint amountOut uint deadline) internal payable returns(uint) {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = router.WETH();
        
        IERC20(USDC).approve(address(router), amount);
        // uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
        router.swapExactTokensForETH(amount, amountOut, path, address(this), deadline);
    }

    function parseRedeemArgs(address oToken, address receiver, uint256 _amount) internal {
        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1); 
        actions[0] = ActionArg({
            actionType: ActionType.redeem,
            owner: address(0),
            secondAddress: receiver,
            asset: oToken,
            vaultId: 0,
            amount: _amount,
            index: 0,
            data: ''
            });
        return actions;
    }


    function exit(address asset, uint amount) external {
        uint userBal = positions[asset][msg.sender].userBalance;
        require( userBal > 0, 'ZERO_BALANCE');
        positions[asset][msg.sender].userBalance = userBal.sub(amount);
        bool success = IERC20(asset).transferFrom(address(this), msg.sender, amount);        
        require success;
    }
}