pragma solidity ^0.6.0;

import './SafeMath.sol';

/*
minimum is 50% of maximum deposited yet or 500 ES

*/

contract TimeAllyPET {
  using SafeMath for uint256;

  struct PETPlan {
    bool isPlanActive;
    uint256 minimumMonthlyCommitmentAmount;
    uint256 monthlyBenefitFactorPerThousand;
  }

  struct PET {
    uint256 planId;
    uint256 initTimestamp;
    uint256 lastAnnuityWithdrawlMonthId;
    uint256 appointeeVotes;
    uint256 numberOfAppointees;
    mapping(uint256 => uint256) monthlyDepositAmount;
    mapping(uint256 => bool) isPowerBoosterWithdrawn;
    mapping(address => bool) nominees;
    mapping(address => bool) appointees;
  }

  address public owner;
  ERC20 public token;

  uint256 constant EARTH_SECONDS_IN_MONTH = 2629744;

  uint256 public pendingBenefitAmountOfAllStakers;
  uint256 public fundsDeposit;

  PETPlan[] public petPlans;
  mapping(address => PET[]) public pets;

  modifier onlyOwner() {
    require(msg.sender == owner, 'only deployer can call');
    _;
  }

  modifier meOrNominee(address _stakerAddress, uint256 _petId) {
    PET storage _pet = pets[_stakerAddress][_petId];

    /// @notice if transacter is not staker, then transacter should be nominee
    if(msg.sender != _stakerAddress) {
      require(_pet.nominees[msg.sender], 'nomination should be there');
    }
    _;
  }

  constructor(ERC20 _token) public {
    owner = msg.sender;
    token = _token;
  }

  function createPETPlan(
    uint256 _minimumMonthlyCommitmentAmount,
    uint256 _monthlyBenefitFactorPerThousand
  ) public onlyOwner {
    petPlans.push(PETPlan({
      isPlanActive: true,
      minimumMonthlyCommitmentAmount: _minimumMonthlyCommitmentAmount,
      monthlyBenefitFactorPerThousand: _monthlyBenefitFactorPerThousand
    }));
    // add an event here
  }

  function addFunds(uint256 _depositAmount) public {

    /// @notice transfer tokens from the donor to contract
    require(
      token.transferFrom(msg.sender, address(this), _depositAmount)
      , 'tokens should be transfered'
    );

    /// @notice increment amount in fundsDeposit
    fundsDeposit = fundsDeposit.add(_depositAmount);

    /// @notice emiting event that funds been deposited
    // emit FundsDeposited(_depositAmount);
  }

  function withdrawFunds(uint256 _withdrawlAmount) public onlyOwner {

    /// @notice check if withdrawing only unutilized tokens
    require(
      fundsDeposit.sub(pendingBenefitAmountOfAllStakers) >= _withdrawlAmount
      , 'cannot withdraw excess funds'
    );

    /// @notice decrement amount in fundsDeposit
    fundsDeposit = fundsDeposit.sub(_withdrawlAmount);

    /// @notice transfer tokens to withdrawer
    token.transfer(msg.sender, _withdrawlAmount);

    /// @notice emit that funds are withdrawn
    // emit FundsWithdrawn(_withdrawlAmount);
  }


  /// in new PET, it is better to also take a first deposit
  function newPET(
    uint256 _planId
  ) public {
    require(
      petPlans[_planId].isPlanActive
      , 'PET plan is not active'
    );

    pets[msg.sender].push(PET({
      planId: _planId,
      initTimestamp: now,
      lastAnnuityWithdrawlMonthId: 0,
      appointeeVotes: 0,
      numberOfAppointees: 0
    }));

    // emit an event here
  }

  function getMonthlyDepositedAmount(
    address _stakerAddress,
    uint256 _petId,
    uint256 _monthId
  ) public view returns (uint256) {
    return pets[_stakerAddress][_petId].monthlyDepositAmount[_monthId];
  }

  function getDepositMonth(
    address _stakerAddress,
    uint256 _petId
  ) public view returns (uint256) {
    return (now - pets[_stakerAddress][_petId].initTimestamp)/EARTH_SECONDS_IN_MONTH + 1;
  }

  function _getBenefitAllocationByDepositAmount(uint256 _amount, uint256 _planId) private returns (uint256) {
    PETPlan storage _petPlan = petPlans[_planId];

    // initialising benefit calculation with deposit amount
    uint256 _benefitAllocation = _amount;

    // if amount more than commitment, consider the deposit amount as double
    if(_amount >= _petPlan.minimumMonthlyCommitmentAmount.div(2)) {
      _benefitAllocation = _benefitAllocation.mul(2);
    }

    // calculate the benefits in 5 years due to this deposit
    _benefitAllocation = _benefitAllocation.mul(_petPlan.monthlyBenefitFactorPerThousand).mul(5).div(1000);

    // adding extra amount in power booster
    if(_amount >= _petPlan.minimumMonthlyCommitmentAmount) {
      _benefitAllocation = _benefitAllocation.add(_amount);
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
    PETPlan storage _petPlan = petPlans[_pet.planId];

    uint256 _depositMonth = getDepositMonth(_stakerAddress, _petId);

    require(_depositMonth <= 12, 'cannot deposit after accumulation period');

    token.transferFrom(msg.sender, address(this), _depositAmount);

    uint256 _updatedDepositAmount = _pet.monthlyDepositAmount[_depositMonth].add(_depositAmount);

    // also calculate old allocation, to adjust it in new allocation
    uint256 _oldBenefitAllocation = _getBenefitAllocationByDepositAmount(
      _pet.monthlyDepositAmount[_depositMonth],
      _pet.planId
    );
    uint256 _extraBenefitAllocation = _getBenefitAllocationByDepositAmount(
      _updatedDepositAmount,
      _pet.planId
    ).sub(_oldBenefitAllocation);

    // here alocate funds for paying annuitity and power booster.
    // also if fund crosses commitment then alocate more funds
    require(
      fundsDeposit.sub(pendingBenefitAmountOfAllStakers) >= _extraBenefitAllocation
      , 'enough funds should exist'
    );

    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(_extraBenefitAllocation);

    /// @dev recording the deposit
    _pet.monthlyDepositAmount[_depositMonth] = _updatedDepositAmount;
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
      uint256 _depositDoneForThis = _pet.monthlyDepositAmount[_modulo==0?12:_modulo];

      if(_depositDoneForThis >= _petPlan.minimumMonthlyCommitmentAmount.div(2)) {
        _depositDoneForThis = _depositDoneForThis.mul(2);
      }

      _sumOfAnnuity = _sumOfAnnuity.add(_depositDoneForThis);
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
    // uint256 _currentAnnuityMonthId = ((now - _pet.initTimestamp).sub(12)) / EARTH_SECONDS_IN_MONTH;

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
      now >= _allowedTimestamp
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
      pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(_annuityBenefit);

      fundsDeposit = fundsDeposit.sub(_annuityBenefit);

      token.transfer(msg.sender, _annuityBenefit);
    }

    // emit an event here
  }

  function _burnPenalisedPowerBoosterTokens(
    address _stakerAddress,
    uint256 _petId
  ) private {
    PET storage _pet = pets[_stakerAddress][_petId];
    PETPlan storage _petPlan = petPlans[_pet.planId];

    uint256 _unachieveTargetCount;
    // uint256 _target = _petPlan.minimumMonthlyCommitmentAmount.div(2);

    for(uint256 _i = 1; _i <= 12; _i++) {
      if(_pet.monthlyDepositAmount[_i] < _petPlan.minimumMonthlyCommitmentAmount) {
        _unachieveTargetCount++;
      }
    }

    uint256 _powerBoosterAmount = calculatePowerBoosterAmount(_stakerAddress, _petId);

    token.burn(_powerBoosterAmount.mul(_unachieveTargetCount));
  }

  function calculatePowerBoosterAmount(
    address _stakerAddress,
    uint256 _petId
  ) public view returns (uint256) {
    PET storage _pet = pets[_stakerAddress][_petId];
    PETPlan storage _petPlan = petPlans[_pet.planId];

    uint256 _totalDeposited;

    for(uint256 _i = 1; _i <= 12; _i++) {
      uint256 _depositDoneForThis = _pet.monthlyDepositAmount[_i];

      if(_depositDoneForThis >= _petPlan.minimumMonthlyCommitmentAmount.div(2)) {
        _depositDoneForThis = _depositDoneForThis.mul(2);
      }

      _totalDeposited = _totalDeposited.add(_depositDoneForThis);
    }

    return _totalDeposited.div(12);
  }

  function withdrawPowerBooster(
    address _stakerAddress,
    uint256 _petId,
    uint256 _powerBoosterId
  ) public meOrNominee(_stakerAddress, _petId) {
    PET storage _pet = pets[_stakerAddress][_petId];
    PETPlan storage _petPlan = petPlans[_pet.planId];

    require(
      1 <= _powerBoosterId && _powerBoosterId <= 12
      , 'id should be in range'
    );

    require(
      !_pet.isPowerBoosterWithdrawn[_powerBoosterId]
      , 'booster already withdrawn'
    );

    require(
      _pet.monthlyDepositAmount[13 - _powerBoosterId] >= _petPlan.minimumMonthlyCommitmentAmount
      , 'target not achieved'
    );

    uint256 _allowedTimestamp = _getNomineeAllowedTimestamp(_stakerAddress, _petId, _powerBoosterId*5+1);

    require(
      now >= _allowedTimestamp
      , 'cannot withdraw early'
    );

    uint256 _powerBoosterAmount = calculatePowerBoosterAmount(_stakerAddress, _petId);

    _pet.isPowerBoosterWithdrawn[_powerBoosterId] = true;

    token.transfer(msg.sender, _powerBoosterAmount);
  }
}

/// @dev For interface requirement
abstract contract ERC20 {
  function transfer(address _to, uint256 _value) public virtual returns (bool success);
  function transferFrom(address _from, address _to, uint256 _value) public virtual returns (bool success);
  function burn(uint256 value) public virtual;
}
