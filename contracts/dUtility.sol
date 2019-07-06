pragma solidity >=0.5.0 <0.6.0;

import "./interfaces/IdUtility.sol";
import "./interfaces/IVerifier.sol";
import "./Mortal.sol";

/**
 * @title Utility onchain settlement verifier.
 * @dev Inherits from IdUtility. This approach is analoguous to UtilityBase.sol but with
 * private energy state changes.
 */
contract dUtility is Mortal, IdUtility {

  struct Household {
    // for checks if household exists
    bool initialized;

    // Hashes of (deltaEnergy+nonce+msg.sender)
    bytes32 renewableEnergy;
    bytes32 nonRenewableEnergy;
  }

  // mapping of all households
  mapping(address => Household) households;

  modifier onlyHousehold(address _household) {
    require(msg.sender == _household, "No permission to access. Only household may access itself.");
    _;
  }

  modifier householdExists(address _household) {
    require(households[_household].initialized, "Household does not exist.");
    _;
  }

  uint256[] public deeds;

  IVerifier private verifier;

  /**
   * @dev Create a household with address _household to track energy production and consumption.
   * Emits NewHousehold when household was added successfully.
   * @param _household address of the household
   * @return success bool if household does not already exists, should only be called by some authority
   */
  function addHousehold(address _household) external onlyOwner() returns (bool) {
    return _addHousehold(_household);
  }

  /**
   * @dev Get energy properties of _household.
   * @param _household address of the household
   * @return Household stats (initialized,
   *                          renewableEnergy,
   *                          nonRenewableEnergy)
   *          of _household if _household exists
   */
  function getHousehold(address _household) external view householdExists(_household) returns (bool, bytes32, bytes32) {
    Household memory hh = households[_household];
    return (
      hh.initialized,
      hh.renewableEnergy,
      hh.nonRenewableEnergy
    );
  }

  /**
   * @dev Removes a household.
   * @param _household address of the household
   * @return success bool if household does not already exists, should only be called by some authority
   */
  function removeHousehold(address _household) external onlyOwner() householdExists(_household) returns (bool) {
    delete households[_household];
  }

  /**
   * @dev Sets the address of a ZoKrates verifier contract.
   * @param _verifier address of a deployed ZoKrates verifier contract
   */
  function setVerifier(address _verifier) external onlyOwner() returns (bool) {
    verifier = IVerifier(_verifier);
    return true;
  }

  /**
   * @dev Verifies netting by using ZoKrates verifier contract.
   * Emits NettingSuccess when netting could be verified
   */
  function verifyNetting(
    uint256[2] calldata _a,
    uint256[2][2] calldata _b,
    uint256[2] calldata _c,
    uint256[2] calldata _input) external returns (bool success) {
    success = verifier.verifyTx(_a, _b, _c, _input);
    if (success) {
      uint256 record = block.number;
      emit NettingSuccess();
      deeds.push(record);
    }
  }

  /**
   * @dev Validates the equality of the given households and their energy hashes against
   * dUtility's own recorded energy hashes (that the household server sent).
   * Emits CheckHashesSuccess on successful validation.
   * Throws when _households and _householdEnergyHashes length are not equal.
   * Throws when an energy change hash mismatch has been found.
   * @param _households array of household addresses to be checked.
   * @param _householdEnergyHashes array of the corresponding energy hashes.
   * @return true, iff, all given household energy hashes are mathes with the recorded energy hashes.
   */
  function checkHashes(address[] memory _households, bytes32[] memory _householdEnergyHashes) public onlyOwner() returns (bool) {
    require(_households.length == _householdEnergyHashes.length, "Households and energy hash array length must be equal.");
    for (uint256 i = 0; i < _households.length; ++i) {
      address addr = _households[i];
      bytes32 energyHash = _householdEnergyHashes[i];
      Household storage hh = households[addr];
      require(hh.renewableEnergy == energyHash, "Household energy hash mismatch.");
    }
    emit CheckHashesSuccess();
    return true;
  }

  /**
   * @return uint256 length of all successfully verified settlements
   */
  function getDeedsLength() external view returns (uint256) {
    return deeds.length;
  }

  /**
   * @dev Updates a household's renewable energy state calling _updateEnergy
   * @param _household address of the household
   * @param _deltaEnergy bytes32 hash of (delta+nonce+senderAddr)
   * @return success bool returns true, if function was called successfully
   */
  function updateRenewableEnergy(address _household, bytes32 _deltaEnergy)
  external
  onlyHousehold(_household)
  returns (bool) {
    _updateEnergy(_household, _deltaEnergy, true);
  }

  /**
   * @dev Updates a household's non-renewable energy state calling _updateEnergy
   * @param _household address of the household
   * @param _deltaEnergy bytes32 hash of (delta+nonce+senderAddr)
   * @return success bool returns true, if function was called successfully
   */
  function updateNonRenewableEnergy(address _household, bytes32 _deltaEnergy)
  external onlyHousehold(_household)
  returns (bool) {
    _updateEnergy(_household, _deltaEnergy, false);
  }

    /**
   * @dev Updates a household's energy state
   * @param _household address of the household
   * @param _deltaEnergy bytes32 hash of (delta+nonce+senderAddr)
   * @param _isRenewable bool indicates whether said energy is renewable or non-renewable
   * @return success bool returns true, if function was called successfully
   */
  function _updateEnergy(address _household, bytes32 _deltaEnergy, bool _isRenewable)
  internal
  householdExists(_household)
  returns (bool) {
    Household storage hh = households[_household];
    if (_isRenewable) {
      hh.renewableEnergy = _deltaEnergy;
      emit RenewableEnergyChanged(_household, _deltaEnergy);
    } else {
      hh.nonRenewableEnergy = _deltaEnergy;
      emit NonRenewableEnergyChanged(_household, _deltaEnergy);
    }
    return true;
  }

  /**
   * @dev see UtilityBase.addHousehold
   * @param _household address of household
   * @return success bool
   */
  function _addHousehold(address _household) internal onlyOwner returns (bool) {
    require(!households[_household].initialized, "Household already exists.");

    // add new household to mapping
    Household storage hh = households[_household];
    hh.initialized = true;
    hh.renewableEnergy = 0;
    hh.nonRenewableEnergy = 0;

    emit NewHousehold(_household);
    return true;
  }
}