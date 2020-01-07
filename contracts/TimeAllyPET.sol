pragma solidity ^0.6.0;

import './SafeMath.sol';

/*

- add missing functionality

- add events

- audit the contract

- rearrange functions

- add comments natspec

- put update plan status function

- add burning event

- check all token transfer non zero txs

- deposit carry forward
done; to be tested

- make top up amount be considered as half for benefits
done;

- consider adding a function in funds bucket contract for reusing it

- add mou time machine for development purpose when deploying on testnet

- 50% PET bounty on topup

- add 12 month deposit together

- add variable monthly commitment by user by selecting plan
done

- remove mou while deploying
*/

/// @title Fund Bucket of TimeAlly Personal EraSwap Teller
/// @author The EraSwap Team
/// @notice The benefits for PET Smart Contract are transparently stored in advance in this contract
contract FundsBucketPET {

  /// @notice address of the maintainer
  address public deployer;

  /// @notice address of Era Swap ERC20 Smart Contract
  ERC20 public token;

  /// @notice address of PET Smart Contract
  address public petContract;

  /// @notice event schema for monitoring funds added by donors
  /// @dev this is parameter less
  event FundsDeposited(
    address _depositer,
    uint256 _depositAmount
  );

  /// @notice event schema for monitoring unallocated fund withdrawn by deployer
  event FundsWithdrawn(
    address _withdrawer,
    uint256 _withdrawAmount
  );

  /// @notice restricting access to some functionalities to deployer
  modifier onlyDeployer() {
    require(msg.sender == deployer, 'only deployer can call');
    _;
  }

  /// @notice this function is used to deploy FundsBucket Smart Contract
  ///   the same time while deploying PET Smart Contract
  /// @dev this smart contract is deployed by PET Smart Contract while being set up
  /// @param _token: is EraSwap ERC20 Smart Contract Address
  /// @param _deployer: is address of the deployer of PET Smart Contract
  constructor(ERC20 _token, address _deployer) public {
    token = _token;
    deployer = _deployer;
    petContract = msg.sender;
  }

  /// @notice this function is used by well wishers to add funds to the fund bucket of PET
  /// @dev ERC20 approve is required to be done for this contract earlier
  /// @param _depositAmount: amount in exaES to deposit
  function addFunds(uint256 _depositAmount) public {
    token.transferFrom(msg.sender, address(this), _depositAmount);

    /// @dev approving the PET Smart Contract in advance
    token.approve(petContract, _depositAmount);

    emit FundsDeposited(msg.sender, _depositAmount);
  }

  /// @notice this function makes it possible for deployer to withdraw unallocated ES
  function withdrawFunds(bool _withdrawEverything, uint256 _withdrawlAmount) public onlyDeployer {
    if(_withdrawEverything) {
      _withdrawlAmount = token.balanceOf(address(this));
    }

    token.transfer(msg.sender, _withdrawlAmount);

    emit FundsWithdrawn(msg.sender, _withdrawlAmount);
  }
}

/// @title TimeAlly Personal EraSwap Teller Smart Contract
/// @author The EraSwap Team
/// @notice Stakes EraSwap tokens with staker
contract TimeAllyPET {
  using SafeMath for uint256;

  /// @notice data structure of a PET Plan
  struct PETPlan {
    bool isPlanActive;
    uint256 minimumMonthlyCommitmentAmount;
    uint256 monthlyBenefitFactorPerThousand;
  }

  /// @notice data structure of a PET Plan
  struct PET {
    uint256 planId;
    uint256 monthlyCommitmentAmount;
    uint256 initTimestamp;
    uint256 lastAnnuityWithdrawlMonthId;
    uint256 appointeeVotes;
    uint256 numberOfAppointees;
    mapping(uint256 => uint256) monthlyDepositAmount;
    mapping(uint256 => bool) isPowerBoosterWithdrawn;
    mapping(address => bool) nominees;
    mapping(address => bool) appointees;
  }

  /// @notice address storage of the deployer
  address public deployer;

  /// @notice address storage of fundsBucket from which tokens to be pulled for giving benefits
  address public fundsBucket;

  /// @notice address storage of Era Swap Token ERC20 Smart Contract
  ERC20 public token;

  /// @dev selected for taking care of leap years such that 1 Year = 365.242 days holds
  uint256 constant EARTH_SECONDS_IN_MONTH = 2629744;

  /// @notice storage for multiple PET plans
  PETPlan[] public petPlans;

  /// @notice storage for PETs deployed by stakers
  mapping(address => PET[]) public pets;

  /// @notice storage for prepaid Era Swaps available for any wallet address
  mapping(address => uint256) public prepaidES;

  /// @notice event schema for monitoring new pets by stakers
  event NewPET (
    address indexed _staker,
    uint256 _petId,
    uint256 _monthlyCommitmentAmount
  );

  /// @notice event schema for monitoring deposits made by stakers to their pets
  event NewDeposit (
    address indexed _staker,
    uint256 indexed _petId,
    uint256 _monthId,
    uint256 _depositAmount,
    uint256 _benefitAllocated,
    address _depositedBy
  );

  /// @notice event schema for monitoring pet annuity withdrawn by stakers
  event AnnuityWithdrawl (
    address indexed _staker,
    uint256 indexed _petId,
    uint256 _fromMonthId,
    uint256 _toMonthId,
    uint256 _withdrawlAmount,
    address _withdrawnBy
  );

  /// @notice event schema for monitoring power booster withdrawn by stakers
  event PowerBoosterWithdrawl (
    address indexed _staker,
    uint256 indexed _petId,
    uint256 _powerBoosterId,
    uint256 _withdrawlAmount,
    address _withdrawnBy
  );

  /// @notice event schema for monitoring power booster withdrawn by stakers
  event NomineeUpdated (
    address indexed _staker,
    uint256 indexed _petId,
    address indexed _nomineeAddress,
    bool _nomineeStatus
  );

  /// @notice event schema for monitoring power booster withdrawls by stakers
  event AppointeeUpdated (
    address indexed _staker,
    uint256 indexed _petId,
    address indexed _appointeeAddress,
    bool _appointeeStatus
  );

  /// @notice event schema for monitoring power booster withdrawls by stakers
  event AppointeeVoted (
    address indexed _staker,
    uint256 indexed _petId,
    address indexed _appointeeAddress
  );

  /// @notice restricting access to some functionalities to deployer
  modifier onlyDeployer() {
    require(msg.sender == deployer, 'only deployer can call');
    _;
  }

  /// @notice restricting access of staker's PET to them and their pet nominees
  modifier meOrNominee(address _stakerAddress, uint256 _petId) {
    PET storage _pet = pets[_stakerAddress][_petId];

    /// @notice if transacter is not staker, then transacter should be nominee
    if(msg.sender != _stakerAddress) {
      require(_pet.nominees[msg.sender], 'nomination should be there');
    }
    _;
  }

  /// @notice sets up TimeAllyPET contract when deployed and also deploys FundsBucket
  /// @param _token: is EraSwap ERC20 Smart Contract Address
  constructor(ERC20 _token) public {
    deployer = msg.sender;
    token = _token;
    fundsBucket = address(new FundsBucketPET(_token, msg.sender));
  }

  /// @notice this function is used to add ES as prepaid for PET
  /// @dev ERC20 approve needs to be done
  /// @param _amount: ES to deposit
  function addToPrepaid(uint256 _amount) public {
    require(token.transferFrom(msg.sender, address(this), _amount));
    prepaidES[msg.sender] = prepaidES[msg.sender].add(_amount);
  }

  /// @notice this function is used to send ES as prepaid for PET
  /// @param _addresses: address array to send prepaid ES for PET
  /// @param _amounts: prepaid ES for PET amounts to send to corresponding addresses
  function sendPrepaidESDifferent(
    address[] memory _addresses,
    uint256[] memory _amounts
  ) public {
    for(uint256 i = 0; i < _addresses.length; i++) {
      prepaidES[msg.sender] = prepaidES[msg.sender].sub(_amounts[i]);
      prepaidES[_addresses[i]] = prepaidES[_addresses[i]].add(_amounts[i]);
    }
  }

  /// @notice this function is used by deployer to create plans for new PETs
  function createPETPlan(
    uint256 _minimumMonthlyCommitmentAmount,
    uint256 _monthlyBenefitFactorPerThousand
  ) public onlyDeployer {
    petPlans.push(PETPlan({
      isPlanActive: true,
      minimumMonthlyCommitmentAmount: _minimumMonthlyCommitmentAmount,
      monthlyBenefitFactorPerThousand: _monthlyBenefitFactorPerThousand
    }));
    // add an event here
  }

  /// in new PET, it is better to also take a first deposit
  function newPET(
    uint256 _planId,
    uint256 _monthlyCommitmentAmount
  ) public {
    require(
      petPlans[_planId].isPlanActive
      , 'PET plan is not active'
    );

    pets[msg.sender].push(PET({
      planId: _planId,
      monthlyCommitmentAmount: _monthlyCommitmentAmount,
      initTimestamp: token.mou(),
      lastAnnuityWithdrawlMonthId: 0,
      appointeeVotes: 0,
      numberOfAppointees: 0
    }));

    // emit an event here
    emit NewPET(
      msg.sender,
      pets[msg.sender].length - 1,
      _monthlyCommitmentAmount
    );
  }

  function getMonthlyDepositedAmount(
    address _stakerAddress,
    uint256 _petId,
    uint256 _monthId
  ) public view returns (uint256) {
    return pets[_stakerAddress][_petId].monthlyDepositAmount[_monthId];
  }

  // function getConsideredMonthlyDepositedAmount(
  //   address _stakerAddress,
  //   uint256 _petId,
  //   uint256 _monthId
  // ) public view returns (uint256) {
  //   PET storage _pet = pets[_stakerAddress][_petId];
  //
  //   return _getConsideredMonthlyDepositedAmount(_stakerAddress, _petId, _monthId - 1, _pet.monthlyDepositAmount[_monthId]);
  // }
  //
  // function _getConsideredMonthlyDepositedAmount(
  //   address _stakerAddress,
  //   uint256 _petId,
  //   uint256 _monthId,
  //   uint256 _carryForward
  // ) private view returns (uint256) {
  //   PET storage _pet = pets[_stakerAddress][_petId];
  //   PETPlan storage _petPlan = petPlans[_pet.planId];
  //
  //   if(_monthId < 1 || 12 < _monthId) {
  //     return _carryForward;
  //   }
  //
  //   uint256 _thisMonthDepositAmount = _pet.monthlyDepositAmount[_monthId];
  //
  //   if(_thisMonthDepositAmount < _petPlan.minimumMonthlyCommitmentAmount) {
  //     _carryForward = _carryForward.add(_thisMonthDepositAmount);
  //   } else {
  //     return _carryForward;
  //   }
  //
  //   if(_carryForward >= _petPlan.minimumMonthlyCommitmentAmount) {
  //     return _carryForward;
  //   }
  //
  //
  //   return _getConsideredMonthlyDepositedAmount(
  //     _stakerAddress,
  //     _petId,
  //     _monthId - 1,
  //     _carryForward
  //   );
  // }

  function getDepositMonth(
    address _stakerAddress,
    uint256 _petId
  ) public view returns (uint256) {
    return (token.mou() - pets[_stakerAddress][_petId].initTimestamp)/EARTH_SECONDS_IN_MONTH + 1;
  }

  function _getTotalDepositedIncludingPET(uint256 _amount, uint256 _monthlyCommitmentAmount) private pure returns (uint256) {
    // PETPlan storage _petPlan = petPlans[_planId];

    uint256 _petAmount;

    if(_amount > _monthlyCommitmentAmount) {
      uint256 _topupAmount = _amount.sub(_monthlyCommitmentAmount);
      _petAmount = _monthlyCommitmentAmount.add(_topupAmount.div(2));
    } else if(_amount >= _monthlyCommitmentAmount.div(2)) {
      _petAmount = _amount;
    }

    return _amount.add(_petAmount);
  }

  function _getBenefitAllocationByDepositAmount(PET storage _pet, uint256 _depositAmount, uint256 _depositMonth) private view returns (uint256) {
    uint256 _planId = _pet.planId;
    uint256 _amount = _depositAmount != 0 ? _depositAmount : _pet.monthlyDepositAmount[_depositMonth];
    uint256 _monthlyCommitmentAmount = _pet.monthlyCommitmentAmount;
    PETPlan storage _petPlan = petPlans[_planId];

    // if amount is less than half then deposit amount is _amount
    // if amount is between half to commitment then amount is 2 * _amount
    // if amount is above commitment then amount + commitment + amount / 2
    // calculate _depositAmountIncludingPET give annuity on this amount

    uint256 _petAmount;

    if(_amount > _monthlyCommitmentAmount) {
      uint256 _topupAmount = _amount.sub(_monthlyCommitmentAmount);
      _petAmount = _monthlyCommitmentAmount.add(_topupAmount.div(2));
    } else if(_amount >= _monthlyCommitmentAmount.div(2)) {
      _petAmount = _amount;
    }

    uint256 _depositAmountIncludingPET = _getTotalDepositedIncludingPET(_amount, _monthlyCommitmentAmount);

    // power booster
    uint256 _benefitAllocation = _petAmount;

    // calculate the benefits in 5 years due to this deposit
    if(_amount >= _monthlyCommitmentAmount.div(2) || _depositMonth == 12) {
      _benefitAllocation = _benefitAllocation.add(
        _depositAmountIncludingPET.mul(_petPlan.monthlyBenefitFactorPerThousand).mul(5).div(1000)
      );
    }

    return _benefitAllocation;
  }

  function makeDeposit(
    address _stakerAddress,
    uint256 _petId,
    uint256 _depositAmount,
    bool _usePrepaidES
  ) public {
    require(_depositAmount > 0, 'deposit amount should be non zero');

    PET storage _pet = pets[_stakerAddress][_petId];
    // PETPlan storage _petPlan = petPlans[_pet.planId];

    uint256 _depositMonth = getDepositMonth(_stakerAddress, _petId);

    require(_depositMonth <= 12, 'cannot deposit after accumulation period');

    if(_usePrepaidES) {
      /// @notice subtracting prepaidES from staker
      prepaidES[msg.sender] = prepaidES[msg.sender].sub(_depositAmount);
    } else {
      /// @notice transfering staker tokens to PET contract
      token.transferFrom(msg.sender, address(this), _depositAmount);
    }

    uint256 _updatedDepositAmount = _pet.monthlyDepositAmount[_depositMonth].add(_depositAmount);

    // uint256 _carryForwardAmount;
    uint256 _previousMonth = _depositMonth - 1;

    while(_previousMonth > 0) {
      if(0 < _pet.monthlyDepositAmount[_previousMonth]
      && _pet.monthlyDepositAmount[_previousMonth] < _pet.monthlyCommitmentAmount.div(2)) {
        _updatedDepositAmount = _updatedDepositAmount.add(_pet.monthlyDepositAmount[_previousMonth]);
        _pet.monthlyDepositAmount[_previousMonth] = 0;
      }
      _previousMonth -= 1;
    }

    // also calculate old allocation, to adjust it in new allocation
    uint256 _oldBenefitAllocation = _getBenefitAllocationByDepositAmount(
      _pet,
      0,
      _depositMonth
    );
    uint256 _extraBenefitAllocation = _getBenefitAllocationByDepositAmount(
      _pet,
      _updatedDepositAmount,
      _depositMonth
    ).sub(_oldBenefitAllocation);

    // here alocate funds for paying annuitity and power booster.
    // also if fund crosses commitment then alocate more funds

    token.transferFrom(fundsBucket, address(this), _extraBenefitAllocation);

    // pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(_extraBenefitAllocation.add(_depositAmount));

    /// @dev recording the deposit
    _pet.monthlyDepositAmount[_depositMonth] = _updatedDepositAmount;

    emit NewDeposit(
      _stakerAddress,
      _petId,
      _depositMonth,
      _depositAmount,
      _extraBenefitAllocation,
      msg.sender
    );
  }

  // function getMonthlyBenefitAmount(
  //   address _stakerAddress,
  //   uint256 _petId,
  //   uint256 _monthId
  // ) public view returns (uint256) {
  //   PET storage _pet = pets[_stakerAddress][_petId];
  //   PETPlan storage _petPlan = petPlans[_pet.planId];
  //
  //   uint256 _modulo = _monthId%12;
  //   uint256 _totalDepositAmount = _pet.monthlyDepositAmount[_modulo==0?12:_modulo];
  //
  //   if(_totalDepositAmount >= _petPlan.minimumMonthlyCommitmentAmount) {
  //     _totalDepositAmount = _totalDepositAmount.mul(2);
  //   }
  //
  //   return _totalDepositAmount.mul(_petPlan.monthlyBenefitFactorPerThousand).div(1000);
  // }

  function getSumOfMonthlyAnnuity(
    address _stakerAddress,
    uint256 _petId,
    uint256 _startAnnuityMonthId,
    uint256 _endAnnuityMonthId
  ) public view returns (uint256) {
    PET storage _pet = pets[_stakerAddress][_petId];
    PETPlan storage _petPlan = petPlans[_pet.planId];

    uint256 _sumOfAnnuity;

    for(uint256 _i = _startAnnuityMonthId; _i <= _endAnnuityMonthId; _i++) {
      uint256 _modulo = _i%12;
      uint256 _depositAmountIncludingPET = _getTotalDepositedIncludingPET(_pet.monthlyDepositAmount[_modulo==0?12:_modulo], _pet.monthlyCommitmentAmount);
      // uint256 _depositAmountIncludingPET = _pet.monthlyDepositAmount[_modulo==0?12:_modulo];

      // if(_depositAmountIncludingPET >= _petPlan.minimumMonthlyCommitmentAmount.div(2)) {
      //   _depositAmountIncludingPET = _depositAmountIncludingPET.mul(2);
      // }

      _sumOfAnnuity = _sumOfAnnuity.add(_depositAmountIncludingPET);
    }

    return _sumOfAnnuity.mul(_petPlan.monthlyBenefitFactorPerThousand).div(1000);
  }

  function _getNomineeAllowedTimestamp(
    address _stakerAddress,
    uint256 _petId,
    uint256 _annuityMonthId
  ) private view returns (uint256) {
    PET storage _pet = pets[_stakerAddress][_petId];
    uint256 _allowedTimestamp = _pet.initTimestamp + (12 + _annuityMonthId - 1) * EARTH_SECONDS_IN_MONTH;

    if(msg.sender != _stakerAddress) {
      if(_pet.appointeeVotes > _pet.numberOfAppointees.div(2)) {
        _allowedTimestamp += EARTH_SECONDS_IN_MONTH * 6;
      } else {
        _allowedTimestamp += EARTH_SECONDS_IN_MONTH * 12;
      }
    }

    return _allowedTimestamp;
  }

  function withdrawAnnuity(
    address _stakerAddress,
    uint256 _petId,
    uint256 _endAnnuityMonthId
  ) public meOrNominee(_stakerAddress, _petId) {
    PET storage _pet = pets[_stakerAddress][_petId];
    uint256 _lastAnnuityWithdrawlMonthId = _pet.lastAnnuityWithdrawlMonthId;
    // uint256 _currentAnnuityMonthId = ((token.mou() - _pet.initTimestamp).sub(12)) / EARTH_SECONDS_IN_MONTH;

    require(
      _lastAnnuityWithdrawlMonthId < _endAnnuityMonthId
      , 'start should be before end'
    );

    require(
      _endAnnuityMonthId <= 60
      , 'only 60 Annuity withdrawls'
    );

    uint256 _allowedTimestamp = _getNomineeAllowedTimestamp(_stakerAddress, _petId, _endAnnuityMonthId);

    require(
      token.mou() >= _allowedTimestamp
      , 'cannot withdraw early'
    );

    uint256 _annuityBenefit = getSumOfMonthlyAnnuity(
      _stakerAddress,
      _petId,
      _lastAnnuityWithdrawlMonthId+1,
      _endAnnuityMonthId
    );

    _pet.lastAnnuityWithdrawlMonthId = _endAnnuityMonthId;

    if(_lastAnnuityWithdrawlMonthId == 0) {
      _burnPenalisedPowerBoosterTokens(_stakerAddress, _petId);
    }

    if(_annuityBenefit != 0) {
      // sub pending benefits
      // pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.sub(_annuityBenefit);

      token.transfer(msg.sender, _annuityBenefit);
    }

    // emit an event here
    emit AnnuityWithdrawl(
      _stakerAddress,
      _petId,
      _lastAnnuityWithdrawlMonthId+1,
      _endAnnuityMonthId,
      _annuityBenefit,
      msg.sender
    );
  }

  function _burnPenalisedPowerBoosterTokens(
    address _stakerAddress,
    uint256 _petId
  ) private {
    PET storage _pet = pets[_stakerAddress][_petId];
    // PETPlan storage _petPlan = petPlans[_pet.planId];

    uint256 _unachieveTargetCount;

    for(uint256 _i = 1; _i <= 12; _i++) {
      if(_pet.monthlyDepositAmount[_i] < _pet.monthlyCommitmentAmount) {
        _unachieveTargetCount++;
      }
    }

    uint256 _powerBoosterAmount = calculatePowerBoosterAmount(_stakerAddress, _petId);

    token.burn(_powerBoosterAmount.mul(_unachieveTargetCount));

    //add burn event here
  }

  function calculatePowerBoosterAmount(
    address _stakerAddress,
    uint256 _petId
  ) public view returns (uint256) {
    PET storage _pet = pets[_stakerAddress][_petId];
    // PETPlan storage _petPlan = petPlans[_pet.planId];

    uint256 _totalDepositedIncludingPET;

    for(uint256 _i = 1; _i <= 12; _i++) {
      // uint256 _depositAmountIncludingPET = _pet.monthlyDepositAmount[_i];
      //
      // if(_depositAmountIncludingPET >= _petPlan.minimumMonthlyCommitmentAmount.div(2)) {
      //   _depositAmountIncludingPET = _depositAmountIncludingPET.mul(2);
      // }

      uint256 _depositAmountIncludingPET = _getTotalDepositedIncludingPET(_pet.monthlyDepositAmount[_i], _pet.monthlyCommitmentAmount);

      _totalDepositedIncludingPET = _totalDepositedIncludingPET.add(_depositAmountIncludingPET);
    }

    return _totalDepositedIncludingPET.div(12);
  }

  function withdrawPowerBooster(
    address _stakerAddress,
    uint256 _petId,
    uint256 _powerBoosterId
  ) public meOrNominee(_stakerAddress, _petId) {
    PET storage _pet = pets[_stakerAddress][_petId];
    // PETPlan storage _petPlan = petPlans[_pet.planId];

    require(
      1 <= _powerBoosterId && _powerBoosterId <= 12
      , 'id should be in range'
    );

    require(
      !_pet.isPowerBoosterWithdrawn[_powerBoosterId]
      , 'booster already withdrawn'
    );

    require(
      _pet.monthlyDepositAmount[13 - _powerBoosterId] >= _pet.monthlyCommitmentAmount
      , 'target not achieved'
    );

    uint256 _allowedTimestamp = _getNomineeAllowedTimestamp(_stakerAddress, _petId, _powerBoosterId*5+1);

    require(
      token.mou() >= _allowedTimestamp
      , 'cannot withdraw early'
    );

    uint256 _powerBoosterAmount = calculatePowerBoosterAmount(_stakerAddress, _petId);

    if(_powerBoosterAmount > 0) {
      _pet.isPowerBoosterWithdrawn[_powerBoosterId] = true;

      // pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.sub(_powerBoosterAmount);

      token.transfer(msg.sender, _powerBoosterAmount);

      emit PowerBoosterWithdrawl(
        _stakerAddress,
        _petId,
        _powerBoosterId,
        _powerBoosterAmount,
        msg.sender
      );
    }
  }

  function viewNomination(
    address _stakerAddress,
    uint256 _petId,
    address _nomineeAddress
  ) public view returns (bool) {
    return pets[_stakerAddress][_petId].nominees[_nomineeAddress];
  }

  function viewAppointation(
    address _stakerAddress,
    uint256 _petId,
    address _appointeeAddress
  ) public view returns (bool) {
    return pets[_stakerAddress][_petId].appointees[_appointeeAddress];
  }

  function appointeeVote(
    address _stakerAddress,
    uint256 _petId
  ) public {
    PET storage _pet = pets[_stakerAddress][_petId];

    /// @notice checking if appointee has rights to cast a vote
    require(_pet.appointees[msg.sender]
      , 'should be appointee to cast vote'
    );

    /// @notice removing appointee's rights to vote again
    _pet.appointees[msg.sender] = false;

    /// @notice adding a vote to PET
    _pet.appointeeVotes = _pet.appointeeVotes.add(1);

    /// @notice emit that appointee has voted
    emit AppointeeVoted(_stakerAddress, _petId, msg.sender);
  }

  function toogleAppointee(
    uint256 _petId,
    address _appointeeAddress,
    bool _newAppointeeStatus
  ) public {
    PET storage _pet = pets[msg.sender][_petId];

    /// @notice if not an appointee already and _newAppointeeStatus is true, adding appointee
    if(!_pet.appointees[_appointeeAddress] && _newAppointeeStatus) {
      _pet.numberOfAppointees = _pet.numberOfAppointees.add(1);
      _pet.appointees[_appointeeAddress] = true;
    }

    /// @notice if already an appointee and _newAppointeeStatus is false, removing appointee
    else if(_pet.appointees[_appointeeAddress] && !_newAppointeeStatus) {
      _pet.appointees[_appointeeAddress] = false;
      _pet.numberOfAppointees = _pet.numberOfAppointees.sub(1);
    }

    emit AppointeeUpdated(msg.sender, _petId, _appointeeAddress, _newAppointeeStatus);
  }

  function toogleNominee(
    uint256 _petId,
    address _nomineeAddress,
    bool _newNomineeStatus
  ) public {

    /// @notice updating nominee status
    pets[msg.sender][_petId].nominees[_nomineeAddress] = _newNomineeStatus;

    /// @notice emiting event for UI and other applications
    emit NomineeUpdated(msg.sender, _petId, _nomineeAddress, _newNomineeStatus);
  }
}

/// @dev For interface requirement
abstract contract ERC20 {
  function balanceOf(address tokenDeployer) public view virtual returns (uint);
  function approve(address delegate, uint numTokens) public virtual returns (bool);
  function transfer(address _to, uint256 _value) public virtual returns (bool success);
  function transferFrom(address _from, address _to, uint256 _value) public virtual returns (bool success);
  function burn(uint256 value) public virtual;
  function mou() public view virtual returns (uint256);
}
