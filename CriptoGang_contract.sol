pragma solidity ^0.8.0;
contract SealedBidAuction {
    enum Phase { Bidding, Reveal, Ended }
    struct EncryptedBid {
        uint256 c1;
        uint256 c2;
        bool    committed;
        uint256 revealedAmount;
        bool    revealed;
        bool    isValid;
        bool    refunded;
    }
    uint256 public constant P = 1000000007;
    uint256 public constant G = 5;
    uint256 public h;          // Clave pública
    uint256 private x;         // Clave privada
    address public organizer;
    string  public auctionItem;
    Phase   public currentPhase;
    uint256 public fixedDeposit;
    uint256 public minimumBid;
    uint256 public biddingDeadline;
    uint256 public revealDeadline;
    address public winner;
    uint256 public winningBid;
    bool    public auctionFinalized;
    mapping(address => EncryptedBid) public bids;
    address[] public bidders;
    event BidCommitted(address indexed bidder, uint256 c1, uint256 c2);
    event BidRevealed(address indexed bidder, uint256 amount, bool valid);
    event AuctionFinalized(address indexed winner, uint256 winningAmount);
    event DepositRefunded(address indexed bidder, uint256 amount);
    event PhaseAdvanced(Phase newPhase);
    modifier onlyOrganizer() {
        require(msg.sender == organizer, "Solo el organizador");
        _;
    }
    modifier inPhase(Phase _p) {
        require(currentPhase == _p, "Fase incorrecta");
        _;
    }
    constructor(
        string memory _auctionItem,
        uint256 _biddingMinutes,
        uint256 _revealMinutes,
        uint256 _fixedDepositWei,
        uint256 _minimumBidWei
    ) {
        require(_fixedDepositWei > 0, "Deposito debe ser > 0");
        require(_minimumBidWei <= _fixedDepositWei, "Puja minima > deposito");
        organizer    = msg.sender;
        auctionItem  = _auctionItem;
        fixedDeposit = _fixedDepositWei;
        minimumBid   = _minimumBidWei;
        currentPhase = Phase.Bidding;
        biddingDeadline = block.timestamp + (_biddingMinutes * 1 minutes);
        revealDeadline  = biddingDeadline + (_revealMinutes * 1 minutes);
        x = (uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            block.number
        ))) % (P - 2)) + 1;
        h = modExp(G, x, P);
    }
    function modExp(
        uint256 base,
        uint256 exponent,
        uint256 modulus
    ) internal view returns (uint256 result) {
        assembly {
            let freeMem := mload(0x40)
            mstore(freeMem, 0x20)
            mstore(add(freeMem, 0x20), 0x20)
            mstore(add(freeMem, 0x40), 0x20)
            mstore(add(freeMem, 0x60), base)
            mstore(add(freeMem, 0x80), exponent)
            mstore(add(freeMem, 0xA0), modulus)
            let success := staticcall(gas(), 0x05, freeMem, 0xC0, freeMem, 0x20)
            if iszero(success) { revert(0, 0) }
            result := mload(freeMem)
        }
    }
    function modInverse(uint256 a, uint256 _p) internal view returns (uint256) {
        return modExp(a, _p - 2, _p);
    }
    function encryptBid(
        uint256 _bidAmountWei,
        uint256 _salt
    ) public view returns (uint256 c1, uint256 c2) {
        require(_bidAmountWei > 0, "Puja debe ser > 0");
        require(_bidAmountWei < P, "Puja debe ser menor que P");
        uint256 k = (uint256(keccak256(abi.encodePacked(
            _salt,
            msg.sender,
            block.timestamp,
            block.prevrandao
        ))) % (P - 2)) + 1;
        c1 = modExp(G, k, P);
        uint256 hk = modExp(h, k, P);
        c2 = mulmod(_bidAmountWei, hk, P);
    }
    function commitBid(uint256 _c1, uint256 _c2)
        external payable inPhase(Phase.Bidding)
    {
        require(block.timestamp <= biddingDeadline, "Plazo de pujas expirado");
        require(msg.value == fixedDeposit, "Enviar exactamente el deposito fijo");
        require(!bids[msg.sender].committed, "Ya has pujado");
        require(_c1 > 0 && _c2 > 0, "Ciphertext invalido");
        bids[msg.sender] = EncryptedBid({
            c1:             _c1,
            c2:             _c2,
            committed:      true,
            revealedAmount: 0,
            revealed:       false,
            isValid:        false,
            refunded:       false
        });
        bidders.push(msg.sender);
        emit BidCommitted(msg.sender, _c1, _c2);
    }
    function advanceToRevealPhase()
        external onlyOrganizer inPhase(Phase.Bidding)
    {
        require(block.timestamp > biddingDeadline, "Plazo de pujas no expirado");
        currentPhase = Phase.Reveal;
        emit PhaseAdvanced(Phase.Reveal);
    }
    function revealAllBids()
        external onlyOrganizer inPhase(Phase.Reveal)
    {
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            EncryptedBid storage b = bids[bidder];
            if (!b.committed || b.revealed) continue;
            uint256 s    = modExp(b.c1, x, P);
            uint256 sInv = modInverse(s, P);
            uint256 m    = mulmod(b.c2, sInv, P);
            b.revealed       = true;
            b.revealedAmount = m;
            if (m >= minimumBid && m <= fixedDeposit) {
                b.isValid = true;
            }
            emit BidRevealed(bidder, m, b.isValid);
        }
    }
    function revealSingleBid(address _bidder)
        external onlyOrganizer inPhase(Phase.Reveal)
    {
        EncryptedBid storage b = bids[_bidder];
        require(b.committed, "Pujador no registrado");
        require(!b.revealed, "Ya revelada");
        uint256 s    = modExp(b.c1, x, P);
        uint256 sInv = modInverse(s, P);
        uint256 m    = mulmod(b.c2, sInv, P);
        b.revealed       = true;
        b.revealedAmount = m;
        if (m >= minimumBid && m <= fixedDeposit) {
            b.isValid = true;
        }
        emit BidRevealed(_bidder, m, b.isValid);
    }
    function finalizeAuction()
        external onlyOrganizer inPhase(Phase.Reveal)
    {
        require(block.timestamp > revealDeadline, "Plazo de revelacion no expirado");
        require(!auctionFinalized, "Ya finalizada");
        currentPhase     = Phase.Ended;
        auctionFinalized = true;
        address highestBidder = address(0);
        uint256 highestBid    = 0;
        for (uint256 i = 0; i < bidders.length; i++) {
            EncryptedBid storage b = bids[bidders[i]];
            if (b.revealed && b.isValid && b.revealedAmount > highestBid) {
                highestBid    = b.revealedAmount;
                highestBidder = bidders[i];
            }
        }
        winner     = highestBidder;
        winningBid = highestBid;
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            EncryptedBid storage b = bids[bidder];
            if (!b.revealed) continue;
            b.refunded = true;
            if (bidder == highestBidder && highestBid > 0) {
                (bool s1, ) = payable(organizer).call{value: highestBid}("");
                require(s1, "Transferencia al organizador fallida");
                uint256 refund = fixedDeposit - highestBid;
                if (refund > 0) {
                    (bool s2, ) = payable(bidder).call{value: refund}("");
                    require(s2, "Reembolso al ganador fallido");
                    emit DepositRefunded(bidder, refund);
                }
            } else {
                (bool s3, ) = payable(bidder).call{value: fixedDeposit}("");
                require(s3, "Reembolso fallido");
                emit DepositRefunded(bidder, fixedDeposit);
            }
        }
        emit AuctionFinalized(winner, winningBid);
        emit PhaseAdvanced(Phase.Ended);
    }
    function claimDeposit() external {
        require(auctionFinalized, "Subasta no finalizada");
        EncryptedBid storage b = bids[msg.sender];
        require(b.committed, "No participaste");
        require(!b.refunded, "Ya reclamado");
        b.refunded = true;
        (bool success, ) = payable(msg.sender).call{value: fixedDeposit}("");
        require(success, "Reembolso fallido");
        emit DepositRefunded(msg.sender, fixedDeposit);
    }
    function getTotalBidders() public view returns (uint256) {
        return bidders.length;
    }
    function getWinner() public view returns (address, uint256) {
        require(auctionFinalized, "No finalizada");
        return (winner, winningBid);
    }
    function getEncryptedBid(address _bidder)
        public view returns (uint256 c1, uint256 c2)
    {
        return (bids[_bidder].c1, bids[_bidder].c2);
    }
    function getTimeRemaining() public view returns (uint256) {
        if (currentPhase == Phase.Bidding) {
            return block.timestamp >= biddingDeadline ? 0 : biddingDeadline - block.timestamp;
        } else if (currentPhase == Phase.Reveal) {
            return block.timestamp >= revealDeadline ? 0 : revealDeadline - block.timestamp;
        }
        return 0;
    }
    function getAuctionInfo()
        public view
        returns (
            string memory item,
            Phase   phase,
            uint256 deposit,
            uint256 minBid,
            uint256 total,
            uint256 timeLeft,
            uint256 publicKey
        )
    {
        return (
            auctionItem, currentPhase, fixedDeposit,
            minimumBid, bidders.length, getTimeRemaining(), h
        );
    }
}
