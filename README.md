SealedBidAuction — README
Sealed-Bid Auction with ElGamal Encryption on Ethereum — UPF Hackathon 2026
1. Scenario
In public blockchain auctions, bids are visible to everyone, enabling front-running and strategic price manipulation. Our smart contract solves this with a sealed-bid auction using ElGamal encryption on-chain. Bids are mathematically encrypted so no participant can read others' bids. The blockchain guarantees trustless execution without a central auctioneer. This makes it ideal for government procurement or exclusive NFT sales where bid secrecy is critical for fairness.
2. Actors and Assumptions
Organizer (trusted): Deploys contract, advances phases, triggers decryption. Cannot falsify results. If they censor a bidder, that bidder can reclaim their deposit via claimDeposit().
Bidders (potentially malicious): Encrypt bids via encryptBid() (view, free), then submit ciphertext via commitBid(c1,c2) with a fixed deposit. No secrets to manage.
Publicly visible: ciphertext (c1,c2), deposit amounts (identical for all), public key h, auction params, final winner.
Not visible: plaintext bid values during bidding phase. Private key x in storage (see Threats).

3. Protocol
Deploy: Organizer deploys with auction parameters. The contract auto-generates a private key x and a public key h = g^x mod p.
Encrypt: Bidder locally calculates ciphertexts (c1, c2) using encryptBid(bid, salt), a free view function that does not write to the blockchain.
Commit: Bidder calls commitBid(c1, c2) while sending the exact fixed deposit. Only the ciphertext goes on-chain.
Reveal: Organizer calls advanceToRevealPhase() then revealAllBids(). The contract decrypts all bids using m = c2 * (c1^x)^-1 mod p.
Finalize: Organizer calls finalizeAuction(). The winning bid is transferred to the Organizer, excess deposit returns to the winner, and full deposits return to non-winners.
Failure Cases: If the Organizer maliciously halts the auction, bidders can use claimDeposit() to recover their funds.
4. Threats and Attacks
Ciphertext Matching Attack (Solved)
The random nonce k used for each bid mitigates brute-force attacks based on ciphertext repetition. Without a nonce, if two users bid the same amount (0.05 ETH for example), both would generate the same (c1​,c2​). An attacker could compare ciphertexts to detect which bids are equal, or even encrypt all possible values and compare them with the stored ciphertexts.
With a different k for each bid, the same amount produces a different ciphertext every time. This is what is known as semantic security (IND-CPA): the ciphertext does not leak any information about the plaintext, not even whether two messages are the same.
Storage Slot Reading (Privacy Compromise)
Attack: Smart contracts cannot hide secrets, even if variables are declared private. An advanced attacker can use JSON-RPC methods (like eth_getStorageAt) to read the private key x directly from the blockchain's memory before the auction ends. With x, they can decrypt all c1 and c2 ciphertexts in real-time, completely breaking the sealed-bid premise.
Mitigation: We acknowledge this architectural limitation for this academic hackathon to demonstrate our understanding of EVM storage. In a production environment, the key pair must be generated off-chain and only submitted to the contract during the Reveal phase, or zero-knowledge proofs should be used.
5. Cryptographic Primitives
Primitive
Usage
Security
ElGamal
Bid encryption/decryption
IND-CPA under DDH assumption. Random k → semantic security.
MODEXP (0x05)
Modular exponentiation on EVM
DLP hardness in Z_p*
Fermat inverse
a⁻¹ mod p = a^(p-2) mod p for decryption
Guaranteed for prime p
keccak256
Key generation (x) and nonce (k)
Preimage + collision resistance


6. How to Reproduce the Demo
Setup: Install MetaMask, switch to Sepolia, get ≥0.5 SepoliaETH from https://sepolia-faucet.pk910.de.
Deploy: Paste contract in Remix, compile, connect MetaMask (Injected Provider), deploy with params.
Bid: Call encryptBid(bid, salt) → copy c1, c2. Set Value = fixed deposit. Call commitBid(c1, c2).
Reveal: As organizer: advanceToRevealPhase() → revealAllBids().
Finalize: finalizeAuction() → getWinner() to see result. Verify refunds on Etherscan.

