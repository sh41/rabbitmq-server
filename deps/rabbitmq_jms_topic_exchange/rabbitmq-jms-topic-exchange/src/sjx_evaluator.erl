%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is Pivotal Software, Inc.
%% Copyright (c) 2012, 2013 Pivotal Software, Inc.  All rights reserved.
%% -----------------------------------------------------------------------------
%% Derived from works which were:
%% Copyright (c) 2002, 2012 Tim Watson (watson.timothy@gmail.com)
%% Copyright (c) 2012, 2013 Steve Powell (Zteve.Powell@gmail.com)
%% -----------------------------------------------------------------------------

%% Evaluate an SQL expression for filtering purposes

%% -----------------------------------------------------------------------------

-module(sjx_evaluator).

-export([evaluate/2]).
%% Evaluation function
%%
%%   Given Headers (a list of keyed typed values), and a
%%   parsed SQL string, evaluate the truth or falsity of the expression.
%%
%%   If an identifier is absent from Headers, or the types do not match the comparisons, the
%%   expression will evaluate to false.

-type itemname() :: binary().
-type itemtype() ::
      'longstr' | 'signedint' | 'byte' | 'double' | 'float' | 'long' | 'short' | 'bool'.
-type itemvalue() :: any().

-type tableitem() :: { itemname(), itemtype(), itemvalue() }.
-type table() :: list(tableitem()).

-type expression() :: any().

-spec evaluate(expression(), table()) -> true | false | error.


evaluate( true,                           _Headers ) -> true;
evaluate( false,                          _Headers ) -> false;

evaluate( {'not', Exp },                   Headers ) -> not3(evaluate(Exp, Headers));
evaluate( {'ident', Ident },               Headers ) -> lookup_value(Headers, Ident);
evaluate( {'is_null', Exp },               Headers ) -> val_of(Exp, Headers) =:= undefined;
evaluate( {'not_null', Exp },              Headers ) -> val_of(Exp, Headers) =/= undefined;
evaluate( { Op, Exp },                     Headers ) -> do_una_op(Op, evaluate(Exp, Headers));

evaluate( {'and', Exp1, Exp2 },            Headers ) -> and3(evaluate(Exp1, Headers), evaluate(Exp2, Headers));
evaluate( {'or', Exp1, Exp2 },             Headers ) -> or3(evaluate(Exp1, Headers), evaluate(Exp2, Headers));
evaluate( {'like', LHS, Patt },            Headers ) -> isLike(val_of(LHS, Headers), Patt);
evaluate( {'not_like', LHS, Patt },        Headers ) -> not3(isLike(val_of(LHS, Headers), Patt));
evaluate( { Op, Exp, {range, From, To} },  Headers ) -> evaluate({ Op, Exp, From, To }, Headers);
evaluate( {'between', Exp, From, To},           Hs ) -> between(evaluate(Exp, Hs), evaluate(From, Hs), evaluate(To, Hs));
evaluate( {'not_between', Exp, From, To},       Hs ) -> not3(between(evaluate(Exp, Hs), evaluate(From, Hs), evaluate(To, Hs)));
evaluate( { Op, LHS, RHS },                Headers ) -> do_bin_op(Op, evaluate(LHS, Headers), evaluate(RHS, Headers));

evaluate( Value,                          _Headers ) -> Value.

not3(true ) -> false;
not3(false) -> true;
not3(_    ) -> undefined.

and3(true,  true ) -> true;
and3(false, _    ) -> false;
and3(_,     false) -> false;
and3(_,     _    ) -> undefined.

or3(false, false) -> false;
or3(true,  _    ) -> true;
or3(_,     true ) -> true;
or3(_,     _    ) -> undefined.

do_una_op(_, undefined)  -> undefined;
do_una_op('-', E) -> -E;
do_una_op('+', E) -> +E;
do_una_op(_,   _) -> error.

do_bin_op(_, undefined, _)  -> undefined;
do_bin_op(_, _, undefined ) -> undefined;
do_bin_op('=' , L, R) -> L == R;
do_bin_op('<>', L, R) -> L /= R;
do_bin_op('>' , L, R) -> L > R;
do_bin_op('<' , L, R) -> L < R;
do_bin_op('>=', L, R) -> L >= R;
do_bin_op('<=', L, R) -> L =< R;
do_bin_op('in', L, R) -> isIn(L, R);
do_bin_op('not_in', L, R) -> not isIn(L, R);
do_bin_op('+' , L, R) -> L + R;
do_bin_op('-' , L, R) -> L - R;
do_bin_op('*' , L, R) -> L * R;
do_bin_op('/' , L, R) when R /= 0 -> L / R;
do_bin_op('/' , L, R) when L > 0 andalso R == 0 -> plus_infinity;
do_bin_op('/' , L, R) when L < 0 andalso R == 0 -> minus_infinity;
do_bin_op('/' , L, R) when L == 0 andalso R == 0 -> nan;
do_bin_op(_,_,_) -> error.

isLike(undefined, _Patt) -> undefined;
isLike(L, {regex, MP}) -> patt_match(L, MP);
isLike(L, {Patt, Esc}) -> patt_match(L, sjx_parser:pattern_of(Patt, Esc)).

patt_match(L, MP) ->
  BS = byte_size(L),
  case re:run(L, MP, [{capture, first}]) of
    {match, [{0, BS}]} -> true;
    _                  -> false
  end.

isIn(_L, []   ) -> false;
isIn( L, [L|_]) -> true;
isIn( L, [_|R]) -> isIn(L,R).

val_of({'ident', Ident}, Hs) -> lookup_value(Hs, Ident);
val_of(Value,           _Hs) -> Value.

between(E, F, T) when E =:= undefined orelse F =:= undefined orelse T =:= undefined -> undefined;
between(Value, Lo, Hi) -> Lo =< Value andalso Value =< Hi.

lookup_value(Table, Key) ->
  case lists:keyfind(Key, 1, Table) of
    {_, longstr,   Value} -> Value;
    {_, signedint, Value} -> Value;
    {_, float,     Value} -> Value;
    {_, double,    Value} -> Value;
    {_, byte,      Value} -> Value;
    {_, short,     Value} -> Value;
    {_, long,      Value} -> Value;
    {_, bool,      Value} -> Value;
    false                 -> undefined
  end.
