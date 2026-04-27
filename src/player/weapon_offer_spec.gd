class_name WeaponOfferSpec
extends Resource

enum OfferType { WEAPON, MODIFIER, REMOVE_MODIFIER }

var type: int = OfferType.WEAPON
var weapon = null
var modifier = null
var suggested_slot: int = 0
