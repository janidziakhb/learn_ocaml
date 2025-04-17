let rec last = function 
  | [] -> None
  | [ x ] -> Some x
  | _ :: t -> last t;;

let rec last_two = function 
  |[] |  [_] -> None
  | [ x; y ] -> Some (x,y)
  | _ :: t -> last_two t;;

let rec at k = function
  |[] -> None
  | i :: t -> if k = 0 then  Some i else at (k-1) t;;

last ["a" ; "b" ; "c" ; "d"];;
last [];;

last_two ["a" ; "b" ; "c" ; "d"];;
last_two ["a"];;

at 1  ["a" ; "b" ; "c" ; "d"];;
at 0  ["a"];;

let rec length = function 
  | _ :: t -> 1 + length t
  | [] -> 0;;

length  ["a" ; "b" ; "c" ; "d"];;
length [];;

let is_palindrome list = 
  list = List.rev list;;

is_palindrome ["a" ; "b" ; "a"];;
is_palindrome ["a"];;
is_palindrome ["a"; "b"];;

(*Task 5 - flattening the list*)
type 'a node =
  | One of 'a 
  | Many of 'a node list

let  flatten list = 
  let rec aux acc = function 
    | [] -> acc
    | One i :: t -> aux (acc @ [i]) t
    | Many l :: t -> aux (aux acc l) t
  in aux [] list;;

flatten [One "a"; Many [One "b"; Many [One "c" ;One "d"]; One "e"]];;

(*Task 6 Compress oprdered list of strings *) 

let rec compress = function 
 | a :: (b :: _ as t) -> if a == b then compress t else a :: compress t
 | t -> t;;

compress ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e"];;
