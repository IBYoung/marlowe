{-# LANGUAGE StrictData     #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE NamedFieldPuns     #-}
module Semantics2 where

import Control.Monad
import Data.List.NonEmpty (NonEmpty(..), (<|))
import qualified Data.List.NonEmpty as NE
import Data.List (find)
import Data.Map (Map)
import qualified Data.Map as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Maybe (fromMaybe)
import Control.Monad ((>=>))

data SetupContract = SetupContract {
    setupBounds :: Bounds,
    setupContract :: Contract
} deriving (Eq, Ord, Show, Read)

data Bounds = Bounds {
    oracleBounds :: Map OracleId Bound,
    choiceBounds :: Map ChoiceId Bound
}
               deriving (Eq, Ord, Show, Read)

newtype CommitId = CommitId Integer deriving (Eq, Ord, Show, Read)
type Party = Integer
type NumChoice = Integer
type Timeout = Integer
type SlotNumber = Integer
type ActionId = Integer
type Money = Integer
type LetLabel = Integer


data Contract =
    Null |
    Commit CommitId Party Value Timeout Contract Contract |
    Pay CommitId CommitId Party Value Timeout Contract Contract |
        -- transfer Value money from CommitId to CommitId owned by Party
    Redeem CommitId | -- withdraw everything left in CommitId
    Both Contract Contract |
    If Observation Contract Contract |
    When [Case] Timeout Contract | -- empty Case list for 'after timeout' semantics
    While Observation Timeout Contract Contract
    -- Let LetLabel Contract Contract |
    -- Use LetLabel
               deriving (Eq, Ord, Show, Read)

data Case = Case Observation Contract
               deriving (Eq, Ord, Show, Read)

data ChoiceId = ChoiceId NumChoice Party
               deriving (Eq, Ord, Show, Read)

data OracleId = OracleId Party
               deriving (Eq, Ord, Show, Read)

type Bound = NonEmpty (Integer, Integer) -- lower/upper bounds are included

data Value = Constant Integer |
             AvailableMoney CommitId |
             AddValue Value Value |
             SubValue Value Value |
             ChoiceValue ChoiceId Value |
             OracleValue OracleId Value |
             CurrentSlot -- ToDo: think about slot intervals
               deriving (Eq, Ord, Show, Read)

data Observation = AndObs Observation Observation |
                   OrObs Observation Observation |
                   NotObs Observation |
                   ChoseSomething ChoiceId |
                   OracleValueProvided OracleId |
                   ValueGE Value Value |
                   ValueGT Value Value |
                   ValueLT Value Value |
                   ValueLE Value Value |
                   ValueEQ Value Value |
                   TrueObs |
                   FalseObs
               deriving (Eq, Ord, Show, Read)

data Input = Input { inputCommand :: InputCommand
                   , inputOracleValues :: Map OracleId Integer
                   , inputChoices :: Map ChoiceId Integer }
               deriving (Eq, Ord, Show, Read)

data InputCommand = Perform (NonEmpty ActionId)
                  | Withdraw Party Money
                  | Evaluate
               deriving (Eq, Ord, Show, Read)


data State = State { stateChoices :: Map ChoiceId Integer
                   , stateBounds  :: Bounds
                   , stateCommits :: Map CommitId (Party, Money)
                   , stateRedeems :: Map Party Money
                   , stateContractTimeout :: Timeout
                   }
               deriving (Eq, Ord, Show, Read)

emptyBounds :: Bounds
emptyBounds = Bounds { oracleBounds = M.empty
                     , choiceBounds = M.empty }

initialiseState :: SetupContract -> State
initialiseState SetupContract{..} =
  State { stateChoices = M.empty
        , stateBounds = setupBounds
        , stateCommits = M.empty
        , stateRedeems = M.empty
        , stateContractTimeout = contractLifespan setupContract
        }

data Environment =
  Environment { envSlotNumber :: SlotNumber
              , envChoices :: Map ChoiceId Integer
              , envBounds :: Bounds
              , envOracles :: Map OracleId Integer
              }

initEnvironment :: SlotNumber -> Input -> State -> Maybe Environment
initEnvironment slotNumber Input{..} State {..}
  | M.null $ M.intersection inputChoices stateChoices = Just $
          Environment { envSlotNumber = slotNumber
                      , envChoices = M.union inputChoices stateChoices
                      , envBounds = stateBounds
                      , envOracles = inputOracleValues
                      }
  | otherwise = Nothing


-- ToDo: Check signatures for choices
applyInput :: SlotNumber -> Signatoires -> Input -> State -> Contract -> Maybe (State, Contract)
applyInput slotNumber signatoires input@Input{..} state contract = do
    env <- initEnvironment slotNumber input state
    let (st, cont) = expireContract slotNumber state contract
    let reducedContract = reduce env st cont
    case inputCommand of
        Withdraw party amount -> do
            let redeems = stateRedeems st
            case M.lookup party redeems of
                Just val | val > amount -> let
                    updatedState = st {
                            stateRedeems = M.adjust (\v -> v - amount) party redeems
                        }
                    in return (updatedState, cont)
        Evaluate -> Just (st, cont)
        Perform actions -> let
            perform (st, cont) actionId = performAction env st actionId cont
            in foldM perform (st, cont) actions


performAction :: Environment -> State -> ActionId -> Contract -> Maybe (State, Contract)
performAction env state actionId contract =
    case transform state actionId 0 contract of
        Left _ -> Nothing
        Right r -> r
  where
    transform :: State -> ActionId -> ActionId -> Contract -> Either Integer (Maybe (State, Contract))
    transform state actionId idx contract
        | idx < actionId = case contract of
            Both c1 c2 -> case transform state actionId (idx + 1) c1 of
                Left idx -> case transform state actionId (idx + 1) c2 of
                    Right (Just (st, c)) -> Right (Just (st, Both c1 c))
                    left -> left
                Right (Just (st, c)) -> Right (Just (st, Both c c2))
            While obs timeout contractWhile fail ->
                case transform state actionId (idx + 1) contractWhile of
                    Right (Just (st, c)) -> Right (Just (st, While obs timeout c fail))
                    left -> left
            _ -> Left idx
        | idx == actionId = case contract of
            Commit commitId party value timeout contract fail -> do
                let evaluatedValue = evalValue env state value
                if evaluatedValue > 0 then let
                    commits = stateCommits state
                    updatedState = state {
                        stateCommits = M.alter (\am -> Just (party, maybe 0 snd am + evaluatedValue)) commitId commits
                    }
                    in Right $ Just (state, contract)
                else Right Nothing
            Pay from to party value timeout contract fail -> do
                let evaluatedValue = evalValue env state value
                let commits = stateCommits state
                let (_, fromBalance) = commits M.! from
                if 0 <= evaluatedValue && evaluatedValue <= fromBalance then let
                    reduceFromAccount = M.adjust (\(party, amount) -> (party, amount - evaluatedValue)) from commits
                    newCommits = M.alter (\v -> case v of
                        Just (p, balance) -> Just (p, balance + evaluatedValue)
                        Nothing -> Just (party, evaluatedValue)) to reduceFromAccount
                    updatedState = state { stateCommits = newCommits }
                    in Right $ Just (state, contract)
                else Right Nothing
            Redeem id -> let
                unclaimedRedeems = stateRedeems state
                commits = stateCommits state
                in case M.lookup id commits of
                    Just (party, balance) -> let
                        newState = state {
                            stateRedeems = M.adjust (+ balance) party unclaimedRedeems,
                            stateCommits = M.adjust (const (party, 0)) id commits
                        }
                        in Right $ Just (newState, Null)
                    _ -> Right Nothing
        | otherwise = Left idx


expireContract :: SlotNumber -> State -> Contract -> (State, Contract)
expireContract slotNumber state contract =
    if isExpired (stateContractTimeout state) slotNumber
    then let
        commits = stateCommits state
        redeems = stateRedeems state
        newRedeems = M.foldr (\(party, balance) reds ->
            M.alter (\redeem -> Just $ fromMaybe 0 redeem + balance) party reds
            ) redeems commits
        in (state { stateCommits = M.empty, stateRedeems = newRedeems }, Null)
    else (state, contract)

-- How much everybody pays or receives in transaction
type TransactionOutcomes = M.Map Party Integer

emptyOutcome :: TransactionOutcomes
emptyOutcome = M.empty

isEmptyOutcome :: TransactionOutcomes -> Bool
isEmptyOutcome trOut = all (== 0) trOut

-- Adds a value to the map of outcomes
addOutcome :: Party -> Integer -> TransactionOutcomes -> TransactionOutcomes
addOutcome party diffValue trOut = M.insert party newValue trOut
  where newValue = case M.lookup party trOut of
                     Just value -> value + diffValue
                     Nothing -> diffValue

-- Add two transaction outcomes together
combineOutcomes :: TransactionOutcomes -> TransactionOutcomes -> TransactionOutcomes
combineOutcomes = M.unionWith (+)

reduce :: Environment -> State -> Contract -> Contract
reduce env state contract = case contract of
    Null -> Null
    Commit _ _ _ timeout _ fail ->
        if isExpired slotNumber timeout
        then go fail
        else contract
    Pay _ _ _ _ timeout _ fail ->
        if isExpired slotNumber timeout
        then go fail
        else contract
    Redeem id -> contract
    Both c1 c2 -> case (go c1, go c2) of
        (Null, c) -> c
        (c, Null) -> c
        (nc1, nc2) -> Both nc1 nc2
    If obs cont1 cont2 ->
        if evalObservation env state obs then go cont1 else go cont2
    When cases timeout timeoutCont ->
        if isExpired slotNumber timeout
        then go timeoutCont
        else case find (\(Case obs _) -> evalObservation env state obs) cases of
                Nothing -> contract
                Just (Case _ sc) -> go sc
    While obs timeout contractWhile contractAfter ->
        if isExpired slotNumber timeout || not (evalObservation env state obs)
        then go contractAfter
        else While obs timeout (go contractWhile) contractAfter
  where slotNumber = envSlotNumber env
        go = reduce env state

type Signatoires = Set Party

getCommitBalance :: CommitId -> State -> Money
getCommitBalance commitId state = case M.lookup commitId (stateCommits state) of
    Just (_, balance) -> balance
    Nothing -> 0

-- Evaluate a value
evalValue :: Environment -> State -> Value -> Integer
evalValue env state value = case value of
    Constant i -> i
    AvailableMoney commitId -> getCommitBalance commitId state
    AddValue lhs rhs -> go lhs + go rhs
    SubValue lhs rhs -> go lhs - go rhs
    ChoiceValue choiceId val ->
        fromMaybe (go val) $ M.lookup choiceId (envChoices env)
    OracleValue oracleId val ->
        fromMaybe (go val) $ M.lookup oracleId (envOracles env)
    CurrentSlot -> envSlotNumber env
  where go = evalValue env state

-- Evaluate an observation
evalObservation :: Environment -> State -> Observation -> Bool
evalObservation env state obs = case obs of
    AndObs lhs rhs -> go lhs && go rhs
    OrObs lhs rhs -> go lhs || go rhs
    NotObs o -> not (go o)
    ChoseSomething choiceId -> choiceId `M.member` envChoices env
    OracleValueProvided oracleId -> oracleId `M.member` envOracles env
    ValueGE lhs rhs -> goValue lhs >= goValue rhs
    ValueGT lhs rhs -> goValue lhs > goValue rhs
    ValueLT lhs rhs -> goValue lhs < goValue rhs
    ValueLE lhs rhs -> goValue lhs <= goValue rhs
    ValueEQ lhs rhs -> goValue lhs == goValue rhs
    TrueObs -> True
    FalseObs -> False
  where go = evalObservation env state
        goValue  = evalValue env state

-- Decides whether something has expired
isExpired :: SlotNumber -> SlotNumber -> Bool
isExpired currSlotNumber expirationSlotNumber = currSlotNumber >= expirationSlotNumber

-- Calculates an upper bound for the maximum lifespan of a contract
contractLifespan :: Contract -> Integer
contractLifespan contract = case contract of
    Null -> 0
    Commit _ _ _ timeout contract1 contract2 ->
        maximum [timeout, contractLifespan contract1, contractLifespan contract2]
    Pay _ _ _ _ timeout contract1 contract2 ->
        maximum [timeout, contractLifespan contract1, contractLifespan contract2]
    Redeem{} -> 0
    Both c1 c2 -> contractLifespan c1 `max` contractLifespan c2
    -- TODO simplify observation and check for always true/false cases
    If _ contract1 contract2 ->
        max (contractLifespan contract1) (contractLifespan contract2)
    When cases timeout subContract -> let
        contractsLifespans = fmap (\(Case _ cont) -> contractLifespan cont) cases
        in maximum (timeout : contractLifespan subContract : contractsLifespans)
    While _ timeout contract1 contract2 ->
        maximum [timeout, contractLifespan contract1, contractLifespan contract2]

inferActions :: Environment -> State -> Contract -> [Contract]
inferActions env state contract = case contract of
    Null -> []
    Commit{} -> [contract]
    Pay{} -> [contract]
    Redeem{} -> [contract]
    Both c1 c2 -> go c1 ++ go c2
    If _ c1 c2 -> error "Should not happen. Looks like you infer action for non-reduced contract. Try reduce it first. If should be reduced automatically"
    When{} -> []
    While _ _ contractWhile _ -> go contractWhile
  where go = inferActions env state

alice, bob, carol :: Party
alice = 1
bob = 2
carol = 3

(|||) :: Observation -> Observation -> Observation
(|||) = OrObs

(&&&) :: Observation -> Observation -> Observation
(&&&) = AndObs

(===) :: Value -> Value -> Observation
(===) = ValueEQ

choseThis :: NumChoice -> ChoiceId -> Observation
choseThis choice choiceId  = (ChoiceValue choiceId (Constant 0) === Constant choice)

majority :: NumChoice -> Observation
majority choice = (chose (ChoiceId 1 alice) &&& (chose (ChoiceId 2 bob) ||| chose (ChoiceId 3 carol)))
    ||| (chose (ChoiceId 2 bob) &&& chose (ChoiceId 3 carol))
  where chose = choseThis choice

-- party1 and (party2 or party3) or (party2 and party3)
majorityAgrees :: Observation
majorityAgrees = majority 1

majorityDisagrees :: Observation
majorityDisagrees = majority 2

escrow :: Contract
escrow = Commit (CommitId alice) alice (Constant 450) 10
    (When  [ Case majorityAgrees
                (Pay (CommitId alice) (CommitId bob) bob (AvailableMoney $ CommitId alice) 90
                    (Redeem (CommitId bob))
                    (Redeem (CommitId alice)))
           , Case majorityDisagrees (Redeem (CommitId alice)) ]
        90 (Redeem (CommitId alice)))
    Null

zeroCouponBondGuaranteed :: Party -> Party -> Party -> Integer -> Integer -> Timeout -> Timeout -> Timeout -> Contract
zeroCouponBondGuaranteed issuer investor guarantor notional discount startDate maturityDate gracePeriod =
    -- prepare money for zero-coupon bond, before it could be used
    Commit (CommitId 1) investor (Constant (notional - discount)) startDate
        -- guarantor commits a 'guarantee' before startDate
        (Commit (CommitId 2) guarantor (Constant notional) startDate
            (When [] startDate
                (Pay (CommitId 1) (CommitId 3) issuer (AvailableMoney $ CommitId 1) (maturityDate - gracePeriod)
                    (Both (Redeem $ CommitId 3) -- issuer can take the money
                        (Commit (CommitId 4) issuer (Constant notional) maturityDate
                            -- if the issuer commits the notional before maturity date pay from it, redeem the 'guarantee'
                            (Pay (CommitId 4) (CommitId 1) investor (AvailableMoney $ CommitId 4)
                                (maturityDate + gracePeriod)
                                (Redeem $ CommitId 1) -- investor can collect his money
                                Null -- investor didn't confirm Pay, guarantor can redeem now, because we've reached contract's timeout
                            )
                            -- pay from the guarantor otherwise
                            (Pay (CommitId 2) (CommitId 1) investor (AvailableMoney $ CommitId 2)
                                (maturityDate + gracePeriod)
                                (Redeem $ CommitId 1) -- investor can collect his money
                                Null -- investor didn't confirm Pay, guarantor can redeem now, because we've reached contract's timeout
                            )
                        )
                    )
                    -- issuer didn't collect the loan, so we return those to investor
                    -- and the guarantor pays the discount
                    (Pay (CommitId 2) (CommitId 1) investor (Constant discount)
                        (maturityDate + gracePeriod)
                        (Both   (Redeem $ CommitId 1) -- investor can collect his money
                                (Redeem $ CommitId 2))
                        Null
                    )
                )
            )
            (Redeem $ CommitId 1) -- guarantor didn't commit, redeem investor commit immediately
        )
        Null
