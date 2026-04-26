class_name ConsoleCommand
extends RefCounted

var name: String
var description: String
var subcommands: Dictionary = {}
var execute: Callable
