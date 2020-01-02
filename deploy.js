const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');

if(!process.argv[2]) {
  throw '\nNOTE: Please pass a file name or all flag, your network (homestead, ropsten, ...) as first comand line argument and private key as second command line argument.\neg => node deploy.js deployall rinkeby 0xa6779f54dc1e9959b81f448769450b97a9fcb2b41c53d4b2ab50e5055a170ce7\n';
}

if(!process.argv[3]) {
  throw '\nNOTE: Please pass your network (homestead, ropsten, ...) as first comand line argument and private key as second command line argument.\neg => node deploy.js deployall rinkeby 0xa6779f54dc1e9959b81f448769450b97a9fcb2b41c53d4b2ab50e5055a170ce7\n';

  if(!['homestead', 'ropsten', 'kovan', 'rinkeby', 'goerli'].includes(process.argv[3])) {
    throw `\nNOTE: Network should be: homestead, ropsten, kovan, rinkeby or goerli\n`
  }
}

if(!process.argv[4]) {
  throw '\nNOTE: Please pass your private key as comand line argument after network.\neg => node deploy.js deployall rinkeby 0xa6779f54dc1e9959b81f448769450b97a9fcb2b41c53d4b2ab50e5055a170ce7\n';
}

const provider = ethers.getDefaultProvider(process.argv[3]);
console.log(`\nUsing ${process.argv[3]} network...`);

console.log('\nLoading wallet...');
const wallet = new ethers.Wallet(process.argv[4], provider);
console.log(`Wallet loaded ${wallet.address}\n`);

const buildFolderPath = path.resolve(__dirname, 'build');

const deployFile = async jsonFileName => {
  console.log(`Preparing to deploy '${jsonFileName}' contract`);
  const jsonFilePath = path.resolve(__dirname, 'build', jsonFileName);
  const contractJSON = JSON.parse(fs.readFileSync(jsonFilePath, 'utf8'));

  const ContractFactory = new ethers.ContractFactory(
    contractJSON.abi,
    contractJSON.evm.bytecode.object,
    wallet
  );

  const contractInstance = await ContractFactory.deploy(...process.argv.slice(5));
  console.log(`Deploying '${jsonFileName}' contract at ${contractInstance.address}\nhttps://${process.argv[3] !== 'homestead' ? process.argv[3] : 'www'}.etherscan.io/tx/${contractInstance.deployTransaction.hash}\nwaiting for confirmation...`);

  await contractInstance.deployTransaction.wait();
  console.log(`Contract is deployed at ${contractInstance.address}\n`);

  const PETPlans = [
    {minimumMonthlyCommitmentAmount: '500', monthlyBenefitFactorPerThousand: '100'},
    {minimumMonthlyCommitmentAmount: '1000', monthlyBenefitFactorPerThousand: '105'},
    {minimumMonthlyCommitmentAmount: '2500', monthlyBenefitFactorPerThousand: '110'},
    {minimumMonthlyCommitmentAmount: '5000', monthlyBenefitFactorPerThousand: '115'},
    {minimumMonthlyCommitmentAmount: '10000', monthlyBenefitFactorPerThousand: '120'}
  ]

  for(const plan of PETPlans) {
    console.log(`Creating PET Plan of ${plan.minimumMonthlyCommitmentAmount} ES user target...`);
    const tx = await contractInstance.functions.createPETPlan(
      ethers.utils.parseEther(plan.minimumMonthlyCommitmentAmount),
      plan.monthlyBenefitFactorPerThousand
    );
    console.log('Waiting for confirmation');
    await tx.wait();
    console.log(`PET Plan of ${plan.minimumMonthlyCommitmentAmount} ES created!\n`);
  }
};

if(process.argv[2] === 'deployall') {
  fs.readdirSync(buildFolderPath).forEach(deployFile);
} else {
  deployFile(process.argv[2]);
}
