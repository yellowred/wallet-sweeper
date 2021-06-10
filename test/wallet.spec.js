// https://github.com/BitGo/eth-multisig-v2/blob/8544002d078d6bebcff4017fda7b40a534087bbe/testrpc/accounts.js#L26
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require('@ethersproject/bignumber/lib/bignumber');


describe('Wallet creation', function() {
  it('multisig wallet', async function() {
    const accounts = await ethers.getSigners();
    const walletFactory = await ethers.getContractFactory("WalletSweeper")

    const wallet = await walletFactory.deploy(
      [
        accounts[0].address,
        accounts[1].address
      ],
      [
        accounts[2].address,
        accounts[3].address
      ]
    );

    await wallet.deployed()

    expect(await wallet.signers(0)).to.equal(accounts[0].address)
    expect(await wallet.signers(1)).to.equal(accounts[1].address)
    
    expect(await wallet.operators(0)).to.equal(accounts[2].address)
    expect(await wallet.operators(1)).to.equal(accounts[3].address)

    expect(await wallet.isSigner(accounts[0].address)).to.equal(true)
    expect(await wallet.isSigner(accounts[3].address)).to.equal(false)
  });

  it('not enough signer addresses', async function() {
    const accounts = await ethers.getSigners();
    const walletFactory = await ethers.getContractFactory("WalletSweeper")

    await expect(walletFactory.deploy(
      [],
      [
        accounts[2].address,
        accounts[3].address
      ]
    )).to.be.reverted
  });
});

describe('Deposits', function() {
  let accounts = null
  let wallet = null

  before(async function() {
    accounts = await ethers.getSigners();
    const walletFactory = await ethers.getContractFactory("WalletSweeper")
    wallet = await walletFactory.deploy(
      [
        accounts[0].address,
        accounts[1].address
      ],
      [
        accounts[2].address,
        accounts[3].address
      ]
    );
  });

  it('Should emit event on deposit', async function() {
    await expect(accounts[0].sendTransaction({
      to: wallet.address,
      value: ethers.utils.parseEther("1.0")
    }))
      .to.emit(wallet, 'Deposited')
      .withArgs(accounts[0].address, ethers.utils.parseEther("1.0"), "0x");
  });
});