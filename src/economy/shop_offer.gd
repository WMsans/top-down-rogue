# src/economy/shop_offer.gd
class_name ShopOffer
extends Resource

var modifier: Modifier
var price: int

func _init(p_modifier: Modifier, p_price: int):
	modifier = p_modifier
	price = p_price
