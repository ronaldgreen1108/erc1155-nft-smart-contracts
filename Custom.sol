// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract Custom is ERC1155Supply, ERC1155Holder {
    struct Sale {
        address seller;
        uint256 price;
        uint256 amount;
    }

    uint256 public totalMinted;
    mapping(uint256 => string) tokenURIs;
    mapping(uint256 => uint256) fractionPrices;
    mapping(uint256 => uint256) maxSupplys;
    mapping(uint256 => address) creators;
    mapping(uint256 => Sale[]) tokenIdToSales;
    mapping(address => mapping(uint256 => Sale[])) private saleTokensBySeller;

    event CreateNFT(
        uint256 tokenId,
        string tokenURI,
        uint256 airdropAmount,
        uint256 maxSupply,
        uint256 fractionPrice,
        address creator
    );
    event Minted(uint256 tokenId, uint256 amount, address minter);
    event SaleCreated(
        address seller,
        uint256 tokenId,
        uint256 price,
        uint256 amount
    );
    event SaleCanceled(
        address seller,
        uint256 tokenId,
        uint256 price,
        uint256 amount
    );
    event SaleSuccess(
        address seller,
        address buyer,
        uint256 tokenId,
        uint256 price,
        uint256 amount
    );

    constructor() ERC1155("Poulina") {}

    function create(
        string memory tokenURI,
        uint256 airdropAmount,
        uint256 mxSpl,
        uint256 frcPrice
    ) external {
        require(mxSpl > 0, "Max Supply Must be bigger than 0");
        tokenURIs[++totalMinted] = tokenURI;
        fractionPrices[totalMinted] = frcPrice;
        maxSupplys[totalMinted] = mxSpl;
        creators[totalMinted] = msg.sender;
        if (airdropAmount > 0) {
            _mint(msg.sender, totalMinted, airdropAmount, "0x0000");
        }
        emit CreateNFT(
            totalMinted,
            tokenURI,
            airdropAmount,
            mxSpl,
            frcPrice,
            msg.sender
        );
    }

    function mint(uint256 tokenId, uint256 amount) external payable {
        require(exists(tokenId) == true, "The Token does not exist");
        require(amount > 0, "Minting 0 is not allowed");
        require(
            totalSupply(tokenId) + amount <= maxSupplys[tokenId],
            "Exceeds Max Supply"
        );
        require(
            msg.value >= fractionPrices[tokenId] * amount,
            "Insufficient funds"
        );
        _mint(msg.sender, tokenId, amount, "0x0000");
        payable(creators[tokenId]).transfer(msg.value);
        emit Minted(tokenId, amount, msg.sender);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        require(exists(tokenId) == true, "The Token does not exist");
        return tokenURIs[tokenId];
    }

    function fractionPrice(uint256 tokenId) external view returns (uint256) {
        require(exists(tokenId) == true, "The Token does not exist");
        return fractionPrices[tokenId];
    }

    function maxSupply(uint256 tokenId) external view returns (uint256) {
        require(exists(tokenId) == true, "The Token does not exist");
        return maxSupplys[tokenId];
    }

    function creator(uint256 tokenId) external view returns (address) {
        require(exists(tokenId) == true, "The Token does not exist");
        return creators[tokenId];
    }

    function createSale(
        uint256 tokenId,
        uint256 price,
        uint256 amount
    ) external {
        require(
            balanceOf(msg.sender, tokenId) >= amount,
            "Insufficient token to create sale"
        );
        safeTransferFrom(msg.sender, address(this), tokenId, amount, "0x0000");
        uint256 i;
        uint256 length = tokenIdToSales[tokenId].length;
        for (
            i = 0;
            i < length &&
                (tokenIdToSales[tokenId][i].seller != msg.sender ||
                    tokenIdToSales[tokenId][i].price != price);
            ++i
        ) {}
        if (i < length) {
            tokenIdToSales[tokenId][i].amount += amount;
        } else {
            tokenIdToSales[tokenId].push(Sale(msg.sender, price, amount));
        }
        length = saleTokensBySeller[msg.sender][tokenId].length;
        for (
            i = 0;
            i < length &&
                saleTokensBySeller[msg.sender][tokenId][i].price != price;
            ++i
        ) {}
        if (i < length) {
            saleTokensBySeller[msg.sender][tokenId][i].amount += amount;
        } else {
            saleTokensBySeller[msg.sender][tokenId].push(
                Sale(msg.sender, price, amount)
            );
        }
        emit SaleCreated(msg.sender, tokenId, price, amount);
    }

    function removeSale(
        address seller,
        uint256 tokenId,
        uint256 price,
        uint256 amount
    ) internal {
        uint256 i;
        uint256 length = tokenIdToSales[tokenId].length;
        for (
            i = 0;
            i < length &&
                (tokenIdToSales[tokenId][i].seller != seller ||
                    tokenIdToSales[tokenId][i].price != price);
            ++i
        ) {}
        require(i < length, "No sale created with this token");
        require(
            tokenIdToSales[tokenId][i].amount >= amount,
            "Insufficient token sale to cancel"
        );
        tokenIdToSales[tokenId][i].amount -= amount;
        length = saleTokensBySeller[seller][tokenId].length;
        for (
            i = 0;
            i < length && saleTokensBySeller[seller][tokenId][i].price != price;
            ++i
        ) {}
        require(i < length, "No sale created with this token");
        require(
            tokenIdToSales[tokenId][i].amount >= amount,
            "Insufficient token sale to cancel"
        );
        saleTokensBySeller[seller][tokenId][i].amount -= amount;
    }

    function cancelSale(
        uint256 tokenId,
        uint256 price,
        uint256 amount
    ) external {
        removeSale(msg.sender, tokenId, price, amount);
        safeTransferFrom(address(this), msg.sender, tokenId, amount, "0x0000");
        emit SaleCanceled(msg.sender, tokenId, price, amount);
    }

    function purchase(
        address seller,
        uint256 tokenId,
        uint256 price,
        uint256 amount
    ) external payable {
        require(seller != msg.sender, "Seller cannot buy his token");
        require(msg.value >= price * amount, "Insufficient fund to buy token");
        removeSale(seller, tokenId, price, amount);
        safeTransferFrom(address(this), msg.sender, tokenId, amount, "0x0000");
        payable(seller).transfer(msg.value);
        emit SaleSuccess(seller, msg.sender, tokenId, price, amount);
    }

    function getSales()
        external
        view
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 length;
        uint256 i;
        for (i = 1; i < totalMinted; ++i) {
            if (exists(i)) {
                length += tokenIdToSales[i].length;
            }
        }
        address[] memory sellers = new address[](length);
        uint256[] memory tokenIds = new uint256[](length);
        uint256[] memory prices = new uint256[](length);
        uint256[] memory amounts = new uint256[](length);
        length = 0;
        uint256 j;
        for (i = 1; i < totalMinted; ++i) {
            if (exists(i)) {
                for (j = 0; j < tokenIdToSales[i].length; ++j) {
                    sellers[length] = tokenIdToSales[i][j].seller;
                    tokenIds[length] = i;
                    prices[length] = tokenIdToSales[i][j].price;
                    amounts[length++] = tokenIdToSales[i][j].amount;
                }
            }
        }
        return (sellers, tokenIds, prices, amounts);
    }

    function getSalesByTokenId(uint256 tokenId)
        external
        view
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 length = tokenIdToSales[tokenId].length;
        uint256 i;
        address[] memory sellers = new address[](length);
        uint256[] memory prices = new uint256[](length);
        uint256[] memory amounts = new uint256[](length);
        for (i = 0; i < length; ++i) {
            sellers[i] = tokenIdToSales[tokenId][i].seller;
            prices[i] = tokenIdToSales[tokenId][i].price;
            amounts[i] = tokenIdToSales[tokenId][i].amount;
        }
        return (sellers, prices, amounts);
    }

    function getSaleTokensBySeller(address seller)
        external
        view
        returns (
            uint256[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 i;
        uint256 j;
        uint256 length;
        uint256 totalCnt;
        for (i = 1; i <= totalMinted; ++i) {
            totalCnt += saleTokensBySeller[seller][i].length;
        }
        uint256[] memory tokenIds = new uint256[](totalCnt);
        uint256[] memory prices = new uint256[](totalCnt);
        uint256[] memory amounts = new uint256[](totalCnt);
        totalCnt = 0;
        for (i = 1; i <= totalMinted; ++i) {
            length = saleTokensBySeller[seller][i].length;
            for (j = 0; j < length; ++j) {
                tokenIds[totalCnt] = i;
                prices[totalCnt] = saleTokensBySeller[seller][i][j].price;
                amounts[totalCnt++] = saleTokensBySeller[seller][i][j].amount;
            }
        }
        return (tokenIds, prices, amounts);
    }

    function getSaleTokensBySellerAndTokenId(address seller, uint256 tokenId)
        external
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256 i;
        uint256 length = saleTokensBySeller[seller][tokenId].length;
        uint256[] memory prices = new uint256[](length);
        uint256[] memory amounts = new uint256[](length);
        for (i = 0; i < length; ++i) {
            prices[i] = saleTokensBySeller[seller][tokenId][i].price;
            amounts[i] = saleTokensBySeller[seller][tokenId][i].amount;
        }
        return (prices, amounts);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == type(ERC1155Holder).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
