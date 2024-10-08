const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = process.env.NFT_ADDRESS; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function setMetadata() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    // metadata = {
    //     value: 100_000000,
    //     couponValue: 0,
    //     issueTimestamp: 1728518400, // 
    //     expirationTimestamp: 1736380800, // 2025-01-09
    //     CUSIP: "912797LX3"
    // };

    metadata = {
        value: 100_000000,
        couponValue: 0,
        issueTimestamp: 1728518400, // 
        expirationTimestamp: 1744243200, // 2025-04-10
        CUSIP: "912797NB9"
    };

    const stringHash = ethers.keccak256(ethers.toUtf8Bytes(metadata.CUSIP));
    const tokenId = BigInt(stringHash).toString();

    console.log("Metadata:", metadata);
    console.log("TokenId: ", tokenId);

    console.log('Setting metadata...');
    const tx = await contract.setMetaData(tokenId, metadata);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

setMetadata();