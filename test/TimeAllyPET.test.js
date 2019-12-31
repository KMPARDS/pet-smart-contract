/*
  Author: Soham Zemse (https://github.com/zemse)

  In this file you should write tests for your smart contract as you progress in developing your smart contract. For reference of Mocha testing framework, you can check out https://devdocs.io/mocha/.
*/

/// @dev importing packages required
const assert = require('assert');
const ethers = require('ethers');
const ganache = require('ganache-cli');

/// @dev initialising development blockchain
const provider = new ethers.providers.Web3Provider(ganache.provider({ gasLimit: 8000000 }));

/// @dev importing build file
const esJson = require('../build/Eraswap_ERC20Basic.json');
const timeallyPETJSON = require('../build/TimeAllyPET_TimeAllyPET.json');

/// @dev initialize global variables
let accounts, esInstance, timeallyPETInstance;

const increaseSeconds = 2629744;
let evm_increasedTime = 2;

const PETPlans = [
  {minimumMonthlyCommitmentAmount: '500', monthlyBenefitFactorPerThousand: '100'},
  {minimumMonthlyCommitmentAmount: '1000', monthlyBenefitFactorPerThousand: '105'},
  {minimumMonthlyCommitmentAmount: '2500', monthlyBenefitFactorPerThousand: '110'},
  {minimumMonthlyCommitmentAmount: '5000', monthlyBenefitFactorPerThousand: '115'},
  {minimumMonthlyCommitmentAmount: '10000', monthlyBenefitFactorPerThousand: '120'}
];

const account1Balance = '80000';
const fundsDeposit = '2000000';
const petPlanId = 2;
const depositCases = [
  ['2000'],
  ['2800'],
  ['4000'],
  ['1000'],
  [],
  ['500'],
  ['2500'],
  ['2500'],
  ['50000'],
  [],
  ['2500'],
  ['1000','500','2000']
];

let nextPowerBoosterWithdrawlMonthId = 1;

/// @dev this is a test case collection
describe('Ganache Setup', async() => {

  /// @dev this is a test case. You first fetch the present state, and compare it with an expectation. If it satisfies the expectation, then test case passes else an error is thrown.
  it('initiates ganache and generates a bunch of demo accounts', async() => {

    /// @dev for example in this test case we are fetching accounts array.
    accounts = await provider.listAccounts();

    /// @dev then we have our expection that accounts array should be at least having 1 accounts
    assert.ok(accounts.length >= 1, 'atleast 2 accounts should be present in the array');
  });
});

describe('Eraswap Setup', () => {
  it('deploys Eraswap ERC20 contract from first account', async() => {

    /// @dev you create a contract factory for deploying contract. Refer to ethers.js documentation at https://docs.ethers.io/ethers.js/html/
    const EraswapContractFactory = new ethers.ContractFactory(
      esJson.abi,
      esJson.evm.bytecode.object,
      provider.getSigner(accounts[0])
    );
    esInstance =  await EraswapContractFactory.deploy();

    assert.ok(esInstance.address, 'conract address should be present');
  });
});

/// @dev this is another test case collection
describe('TimeAllyPET Contract', () => {

  /// @dev describe under another describe is a sub test case collection
  describe('TimeAllyPET Setup', async() => {

    /// @dev this is first test case of this collection
    it('deploys TimeAllyPET contract from first account', async() => {

      /// @dev you create a contract factory for deploying contract. Refer to ethers.js documentation at https://docs.ethers.io/ethers.js/html/
      const TimeAllyPETContractFactory = new ethers.ContractFactory(
        timeallyPETJSON.abi,
        timeallyPETJSON.evm.bytecode.object,
        provider.getSigner(accounts[0])
      );
      timeallyPETInstance =  await TimeAllyPETContractFactory.deploy(esInstance.address);

      assert.ok(timeallyPETInstance.address, 'conract address should be present');
    });

    /// @dev this is second test case of this collection
    it('value should be set properly while deploying', async() => {

      /// @dev you access the value at storage with ethers.js library of our custom contract method called getValue defined in contracts/TimeAllyPET.sol
      const ownerAddress = await timeallyPETInstance.functions.owner();
      const tokenAddress = await timeallyPETInstance.functions.token();

      /// @dev then you compare it with your expectation value
      assert.equal(
        ownerAddress,
        accounts[0],
        'owner address used while deploying must be visible when get'
      );
      assert.equal(
        tokenAddress,
        esInstance.address,
        'token address set while deploying must be visible when get'
      );
    });

    it(`deployer sends ${account1Balance} ES to account 1`, async() => {
      await esInstance.functions.transfer(
        accounts[1],
        ethers.utils.parseEther(account1Balance)
      );

      const balanceOf1 = await esInstance.functions.balanceOf(accounts[1]);

      assert.ok(balanceOf1.eq(ethers.utils.parseEther(account1Balance)), `account 1 should get ${account1Balance} ES`);
    });

    PETPlans.forEach((plan, index) => {
      it('owner should be able to create a new PET Plan of minimum comitment '+plan.minimumMonthlyCommitmentAmount+' ES', async() => {
        const minimumMonthlyCommitmentAmount = ethers.utils.parseEther(plan.minimumMonthlyCommitmentAmount);

        await timeallyPETInstance.functions.createPETPlan(
          minimumMonthlyCommitmentAmount,
          plan.monthlyBenefitFactorPerThousand
        );

        const petPlan = await timeallyPETInstance.functions.petPlans(index);
        // console.log(petPlan);

        assert.ok(petPlan[0], 'plan should be active');
        assert.ok(petPlan[1].eq(minimumMonthlyCommitmentAmount), 'minimumMonthlyCommitmentAmount should be properly set');
        assert.ok(petPlan[2].eq(plan.monthlyBenefitFactorPerThousand), 'monthlyBenefitFactorPerThousand should be properly set');
      });
    });

    it(`owner gives allowance of ${fundsDeposit} ES to PET contract`, async() => {
      const approvalAmount = ethers.utils.parseEther(fundsDeposit);
      await esInstance.functions.approve(timeallyPETInstance.address, approvalAmount);

      const allowance = await esInstance.functions.allowance(accounts[0], timeallyPETInstance.address);

      assert.ok(allowance.eq(approvalAmount), 'allowance should be set');
    });

    it(`owner should be able to fund ${fundsDeposit} ES to the fundDeposit`, async() => {
      const balanceBefore = await esInstance.functions.balanceOf(accounts[0]);
      const fundsDepositBefore = await timeallyPETInstance.functions.fundsDeposit();

      const depositAmount = ethers.utils.parseEther(fundsDeposit);
      const petId = 0;

      await timeallyPETInstance.functions.addFunds(
        depositAmount
      );

      const balanceAfter = await esInstance.functions.balanceOf(accounts[0]);
      const fundsDepositAfter = await timeallyPETInstance.functions.fundsDeposit();

      assert.ok(
        fundsDepositAfter.sub(fundsDepositBefore).eq(depositAmount),
        'increase in fundsDeposit should be deposit amount'
      );

      assert.ok(
        balanceBefore.sub(balanceAfter).eq(depositAmount),
        'balance difference should be deposit amount'
      );
    });

  });

  describe('TimeAllyPET New PET', async() => {
    /// @dev this is first test case of this collection
    it('Account 1 should be able to create new PET', async() => {
      const _timeallyPETInstance = timeallyPETInstance.connect(provider.getSigner(accounts[1]));

      const planId = petPlanId;

      /// @dev you sign and submit a transaction to local blockchain (ganache) initialized on line 10.
      await _timeallyPETInstance.functions.newPET(planId);

      /// @dev now get the value at storage
      const pet = await timeallyPETInstance.functions.pets(accounts[1], 0);

      console.log(pet);

      /// @dev then comparing with expectation value
      assert.ok(
        pet[0].eq(planId),
        'plan id must be set properly'
      );
      assert.ok(
        pet[1].gt(0),
        'timestamp should be non zero'
      );
    });

    depositCases.forEach((monthDepositArray, index) => {
      describe(`Depositing during month ${index+1}`, async() => {
        monthDepositArray.forEach(partDepositAmount => {
          describe(`Account 1 makes deposit of ${partDepositAmount} ES to their PET`, async() => {
            it('account 1 gives allowance of 500 ES to PET contract', async() => {
              const _esInstance = esInstance.connect(provider.getSigner(accounts[1]));

              const approvalAmount = ethers.utils.parseEther(partDepositAmount);
              await _esInstance.functions.approve(timeallyPETInstance.address, approvalAmount);

              const allowance = await _esInstance.functions.allowance(accounts[1], timeallyPETInstance.address);

              assert.ok(allowance.eq(approvalAmount), 'allowance should be set');
            });

            it('account 1 should be able to make a deposit', async() => {
              const _timeallyPETInstance = timeallyPETInstance.connect(provider.getSigner(accounts[1]));

              const balanceBefore = await esInstance.functions.balanceOf(accounts[1]);
              const monthlyDepositAmountBefore = await timeallyPETInstance.functions.getMonthlyDepositedAmount(accounts[1],0,index+1);
              const allocatedFundsBefore = await timeallyPETInstance.functions.pendingBenefitAmountOfAllStakers();

              const depositAmount = ethers.utils.parseEther(partDepositAmount);
              const petId = 0;

              await _timeallyPETInstance.functions.makeDeposit(
                accounts[1], petId, depositAmount, false
              );

              const balanceAfter = await esInstance.functions.balanceOf(accounts[1]);
              const monthlyDepositAmountAfter = await timeallyPETInstance.functions.getMonthlyDepositedAmount(accounts[1],0,index+1);
              const allocatedFundsAfter = await timeallyPETInstance.functions.pendingBenefitAmountOfAllStakers();


              const pet = await timeallyPETInstance.functions.pets(accounts[1], 0);

              console.log('Addition to pending Benefits (annuitity and power booster):', ethers.utils.formatEther(allocatedFundsAfter.sub(allocatedFundsBefore)));

              for(let i = 0; i <= 13; i++) {
                console.log(i, ethers.utils.formatEther(await timeallyPETInstance.functions.getMonthlyDepositedAmount(accounts[1],0,i)));
              }

              assert.ok(
                monthlyDepositAmountAfter.sub(monthlyDepositAmountBefore).eq(depositAmount),
                'increase in monthly deposit should be deposit amount'
              );

              assert.ok(
                balanceBefore.sub(balanceAfter).eq(depositAmount),
                'balance difference should be deposit amount'
              );
            });
          });
        });
        describe('TimeTravel', async() => {
          it(`Traveling to future by ${increaseSeconds} seconds / about one month`, async() => {
            evm_increasedTime += increaseSeconds;
            const timeIncreased = await provider.send('evm_increaseTime', [increaseSeconds]);

            assert.ok(Math.abs(timeIncreased - evm_increasedTime) < 10, 'increase in time should be one month');
          });
        });
      });
    });

    describe('Benefits', async() => {
      it('Seeing benefit', async() => {
        for(let i = 1; i <= 30; i++) {
          console.log(
            i%12||12,
            // ethers.utils.formatEther(await timeallyPETInstance.functions.getMonthlyDepositedAmount(accounts[1],0,i)),
            // ethers.utils.formatEther(await timeallyPETInstance.functions.getMonthlyBenefitAmount(accounts[1],0,i)),
            ethers.utils.formatEther(await timeallyPETInstance.functions.getSumOfMonthlyAnnuity(accounts[1],0,i,i)),
          );
        }
      });

      [...Array(60).keys()].map(n=>n+1).forEach(annuityMonthId => {
        describe(`Benefit period ${annuityMonthId} month`, async() => {
          describe('Annuity', async() => {
            it(`Traveling to future by ${increaseSeconds} seconds / about one month`, async() => {
              evm_increasedTime += increaseSeconds;
              const timeIncreased = await provider.send('evm_increaseTime', [increaseSeconds]);

              assert.ok(Math.abs(timeIncreased - evm_increasedTime) < 10, 'increase in time should be one month');
            });

            // if(annuityMonthId%12) {
            //   return;
            // }

            it(`Withdrawing Annuity for Benefit Month ${annuityMonthId} or Actual ${annuityMonthId+12}`, async() => {
              const _timeallyPETInstance = timeallyPETInstance.connect(provider.getSigner(accounts[1]));

              const balanceBefore = await esInstance.functions.balanceOf(accounts[1]);

              await _timeallyPETInstance.functions.withdrawAnnuity(
                accounts[1],
                0,
                annuityMonthId
              );

              const balanceAfter = await esInstance.functions.balanceOf(accounts[1]);

              console.log(`AN ${annuityMonthId}/${annuityMonthId}) Received:`, ethers.utils.formatEther(balanceAfter.sub(balanceBefore)));

            });
          });

          if(annuityMonthId%5===0 && nextPowerBoosterWithdrawlMonthId+1 <= 12){
            describe(`Power Booster`, async() => {
              it(`Powerbooster Withdrawl during ${annuityMonthId}`, async() => {
                console.log('\t\tPower Booster Withdrawl ID: '+ nextPowerBoosterWithdrawlMonthId);
                const _timeallyPETInstance = timeallyPETInstance.connect(provider.getSigner(accounts[1]));

                const balanceBefore = await esInstance.functions.balanceOf(accounts[1]);

                try {
                  await _timeallyPETInstance.functions.withdrawPowerBooster(
                    accounts[1],
                    0,
                    nextPowerBoosterWithdrawlMonthId
                  );

                  const balanceAfter = await esInstance.functions.balanceOf(accounts[1]);

                  console.log(`PB ${nextPowerBoosterWithdrawlMonthId}/${annuityMonthId}) Received:`, ethers.utils.formatEther(balanceAfter.sub(balanceBefore)));

                  nextPowerBoosterWithdrawlMonthId++;
                } catch(error) {
                  // console.log(error.message, error.message.includes('target not achieved'));
                  if(error.message.includes('target not achieved')) {
                    // console.log(nextPowerBoosterWithdrawlMonthId);
                    nextPowerBoosterWithdrawlMonthId++;
                    // console.log(nextPowerBoosterWithdrawlMonthId);
                  }
                  throw error;
                }
              });
            });
          }
        });

      });
    });

  });
});
