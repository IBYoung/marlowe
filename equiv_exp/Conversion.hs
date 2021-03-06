module Conversion where

import qualified Semantics as Old
import qualified Minimal as New
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Ord (comparing)
import Data.List (genericTake, genericDrop, genericLength, sortBy)

type LastUsedChoice = M.Map Old.Person New.NumChoice

maxUsedChoicesVal :: Old.Value -> LastUsedChoice
maxUsedChoicesVal value =
  case value of
    Old.CurrentBlock -> M.empty
    Old.Committed _ -> M.empty
    Old.Constant _ -> M.empty 
    Old.NegValue v -> goV v
    Old.AddValue v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.SubValue v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.MulValue v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.DivValue v1 v2 v3 -> joinRes $ map goV $ [v1, v2, v3]
    Old.ModValue v1 v2 v3 -> joinRes $ map goV $ [v1, v2, v3]
    Old.ValueFromChoice (nc, per) v -> joinRes $ [M.singleton per nc, goV v]
    Old.ValueFromOracle _ v -> goV v 
  where goV = maxUsedChoicesVal
        joinRes = M.unionsWith (max)

maxUsedChoicesObs :: Old.Observation -> LastUsedChoice
maxUsedChoicesObs observation =
  case observation of
    Old.BelowTimeout _ -> M.empty
    Old.AndObs o1 o2 -> joinRes $ map goO $ [o1, o2]
    Old.OrObs o1 o2 -> joinRes $ map goO $ [o1, o2]
    Old.NotObs o -> goO o
    Old.ChoseThis (nc, per) _ -> M.singleton per nc
    Old.ChoseSomething (nc, per) -> M.singleton per nc
    Old.ValueGE v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.ValueGT v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.ValueLT v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.ValueLE v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.ValueEQ v1 v2 -> joinRes $ map goV $ [v1, v2]
    Old.TrueObs -> M.empty
    Old.FalseObs -> M.empty
  where goO = maxUsedChoicesObs
        goV = maxUsedChoicesVal
        joinRes = M.unionsWith (max)
 
maxUsedChoices :: Old.Contract -> LastUsedChoice
maxUsedChoices contract =
  case contract of
    Old.Null -> M.empty
    Old.Commit _ _ _ v _ _ c1 c2 -> joinRes $ (goV v):(map goC [c1, c2])
    Old.Pay _ _ _ v _ c1 c2 -> joinRes $ (goV v):(map goC [c1, c2])
    Old.Both c1 c2 -> joinRes $ map goC $ [c1, c2]
    Old.Choice o c1 c2 -> joinRes $ (goO o):(map goC [c1, c2])
    Old.When o _ c1 c2 -> joinRes $ (goO o):(map goC [c1, c2])
    Old.While o _ c1 c2 -> joinRes $ (goO o):(map goC [c1, c2])
    Old.Scale v1 v2 v3 c -> joinRes $ (goC c):(map goV [v1, v2, v3])
    Old.Let _ c1 c2 -> joinRes $ map goC $ [c1, c2]
    Old.Use _ -> M.empty
  where goC = maxUsedChoices
        goO = maxUsedChoicesObs
        goV = maxUsedChoicesVal
        joinRes = M.unionsWith (max)

data ActionData =
 ActionData { idActionChoice :: M.Map Old.IdAction New.ChoiceId
            , commitIdCom :: M.Map Old.Person (S.Set Old.IdCommit)
            , commitPerson :: M.Map Old.IdCommit Old.Person
            , commitIdAc :: M.Map Old.IdCommit (S.Set Old.IdAction)
            , payIdAc :: M.Map Old.IdCommit (S.Set Old.IdAction) }
  deriving (Eq,Ord,Show,Read)

emptyActionData :: ActionData
emptyActionData = ActionData M.empty M.empty M.empty M.empty M.empty

addCommit :: Integer -> Old.IdAction -> Old.Person -> ActionData -> ActionData
addCommit cid aid per ac@(ActionData { idActionChoice = iac 
                                     , commitIdCom = cic
                                     , commitPerson = cp
                                     , commitIdAc = cia}) =
  let result = ac{ idActionChoice = M.insert aid (New.ChoiceId cid per) iac
                 , commitIdCom = M.insertWith (S.union) per (S.singleton cid) cic
                 , commitPerson = M.insert cid per cp
                 , commitIdAc = M.insertWith (S.union) cid (S.singleton aid) cia } in
  case M.lookup cid cp of
    Just y -> if y /= per then error "A commitId can only belong to a single person"
              else result
    Nothing -> result

addPay :: Integer -> Old.IdAction -> Old.Person -> ActionData -> ActionData
addPay cid aid per ac@(ActionData { idActionChoice = iac
                                  , payIdAc = pia }) =
  ac{ idActionChoice = M.insert aid (New.ChoiceId cid per) iac
    , payIdAc = M.insertWith (S.union) cid (S.singleton aid) pia }

getNewChoiceNum :: Old.Person -> LastUsedChoice -> (LastUsedChoice, Old.Person)
getNewChoiceNum per luc =
  case M.lookup per luc of
    Just x -> let nx = x + 1 in (M.insert per nx luc, nx)
    Nothing -> (M.insert per 1 luc, 1)

idActionToChoice :: ActionData -> LastUsedChoice -> Old.Contract
                   -> (ActionData, LastUsedChoice)
idActionToChoice ad luc contract =
  case contract of
    Old.Null -> (ad, luc)
    Old.Commit ida _ per _ _ _ c1 c2 ->
      let (nluc, cid) = getNewChoiceNum per luc in
      chain (addCommit cid ida per ad) nluc c1 c2
    Old.Pay ida _ per _ _ c1 c2 ->
      let (nluc, cid) = getNewChoiceNum per luc in
      chain (addPay cid ida per ad) nluc c1 c2
    Old.Both c1 c2 -> chain2 c1 c2
    Old.Choice _ c1 c2 -> chain2 c1 c2
    Old.When _ _ c1 c2 -> chain2 c1 c2
    Old.While _ _ c1 c2 -> chain2 c1 c2
    Old.Scale _ _ _ c -> idActionToChoice ad luc c
    Old.Let _ c1 c2 -> chain2 c1 c2
    Old.Use _ -> (ad, luc)
  where chain2 = chain ad luc
        chain oad oluc c1 c2 = let (adt, luct) = idActionToChoice oad oluc c1 in
                                   idActionToChoice adt luct c2

data QuiescentThread =
    QExpCommit Old.IdCommit Old.Timeout
  | QWhile Old.Observation Old.Timeout Old.Contract
  | QCommit Old.IdAction Old.IdCommit Old.Person Old.Value Old.Timeout Old.Timeout Old.Contract Old.Contract
  | QPay Old.IdAction Old.IdCommit Old.Person Old.Value Old.Timeout Old.Contract Old.Contract
  | QWhen Old.Observation Old.Timeout Old.Contract


data ConvertEnv = ConvertEnv { commits :: M.Map Old.IdCommit Old.Timeout
                             , pays :: S.Set Old.IdAction
                             , minimumBlock :: Old.BlockNumber }
  deriving (Eq,Ord,Show,Read)

emptyConvertEnv :: ConvertEnv
emptyConvertEnv = ConvertEnv M.empty S.empty 0

unfoldChoicesAux :: ConvertEnv -> Old.Contract ->
                    Maybe (Old.Observation, (Bool -> Old.Contract))
unfoldChoicesAux env@(ConvertEnv { minimumBlock = mi }) contract =
  case contract of
    Old.Null -> Nothing 
    Old.Commit _ _ _ _ _ t _ c2 -> if (t <= mi) then unfoldChoicesAux env c2
                                                else Nothing
    Old.Pay _ _ _ _ t _ c2 -> if (t <= mi) then unfoldChoicesAux env c2
                                          else Nothing
    Old.Both c1 c2 ->
      case (unfoldChoicesAux env c1, unfoldChoicesAux env c2) of
        (Just (no, f), _) -> Just (no, (\x -> Old.Both (f x) c2))
        (Nothing, Just (no, f)) -> Just (no, (\x -> Old.Both c1 (f x)))
        (Nothing, Nothing) -> Nothing
    Old.Choice o c1 c2 -> Just (o, (\x -> if x then c1 else c2)) 
    Old.When _ _ _ _ -> Nothing 
    Old.While o t c1 c2 -> do (no, f) <- unfoldChoicesAux env c1
                              return (no, (\x -> Old.While o t (f x) c2))
    Old.Scale _ _ _ _ -> error "Scale not implemented" 
    Old.Let _ _ _ -> error "Expand contract before converting" 
    Old.Use _ -> error "Expand contract before converting"

unfoldChoices :: ConvertEnv -> Old.Contract -> Old.Contract
unfoldChoices env c =
  case unfoldChoicesAux env c of
    Nothing -> c
    Just (o, f) -> let nc1 = unfoldChoices env $ f True in
                   let nc2 = unfoldChoices env $ f False in
                   Old.Choice o nc1 nc2 

-- Taken from: https://mail.haskell.org/pipermail/libraries/2008-February/009270.html
select :: [a] -> [(a,[a])]
select [] = []
select (x:xs) = (x,xs) : [(y,x:ys) | (y,ys) <- select xs]

addValues :: [New.Value] -> New.Value
addValues [x] = x
addValues l = New.AddValue (addValues fp) (addValues sp)
  where fp = genericTake hl l
        sp = genericDrop hl l
        hl = (genericLength l) `div` (2 :: Integer)

remMoney :: ActionData -> S.Set Old.IdCommit -> Old.IdCommit -> New.Value
remMoney ad vpays cid = New.SubValue (addValues cias) (addValues pias)
  where Just ciacs = M.lookup cid $ commitIdAc ad
        Just piacs = M.lookup cid $ payIdAc ad
        cias = [ let Just choid = M.lookup c $ idActionChoice ad in
                 New.ChoiceValue choid (New.Constant 0) | c <- (S.toList ciacs) ]
        pias = [ let Just choid = M.lookup p $ idActionChoice ad in
                 New.ChoiceValue choid (New.Constant 0) | p <- (S.toList piacs)
                                                        , not (p `S.member` vpays) ]

refundEverything :: ActionData -> S.Set Old.IdCommit ->
                    [(Old.IdCommit, Old.Timeout)] -> New.Contract
refundEverything _ _ [] = New.Pay [] (Left 1) -- Just pay residue to first participant,
                                              -- there should be no residue 
refundEverything _ _ [(oid, tim)] = New.When [] tim $ New.Pay [] (Left oid)
refundEverything ad vpays ((oid, tim):(t@(_:_))) =
  New.When [] tim (New.Pay [(s, p)] $ Right $ refundEverything ad vpays t) 
  where 
    Just p = M.lookup oid $ commitPerson ad
    s = remMoney ad vpays oid

flattenQuiescent = flattenQuiescent

getQuiescent = getQuiescent

convertVal :: ActionData -> ConvertEnv -> Old.Value -> New.Value
convertVal ad ce obs =
 case obs of
   Old.CurrentBlock -> New.CurrentSlot
   Old.Committed idCommit ->
     case M.lookup idCommit $ commits ce of
       Nothing -> New.Constant 0
       Just cid -> remMoney ad (pays ce) cid 
   Old.Constant integer -> New.Constant integer
   Old.NegValue _ -> error "NegValue not implemented" 
   Old.AddValue value1 value2 -> New.AddValue (go value1) (go value2)
   Old.SubValue value1 value2 -> New.SubValue (go value1) (go value2)
   Old.MulValue _ _ -> error "MulValue not implemented" 
   Old.DivValue _ _ _ -> error "DivValue not implemented" 
   Old.ModValue _ _ _ -> error "ModValue not implemented" 
   Old.ValueFromChoice (idChoice, idPer) value ->
     New.ChoiceValue (New.ChoiceId idChoice idPer) (go value)
   Old.ValueFromOracle idOracle value ->
     New.OracleValue (New.OracleId idOracle) (go value)
  where
    go = convertVal ad ce

convertObs :: ActionData -> ConvertEnv -> Old.Observation -> New.Observation
convertObs ad ce obs =
 case obs of
   Old.BelowTimeout timeout -> New.ValueLT (New.CurrentSlot) (New.Constant timeout)
   Old.ChoseThis (idChoice, idPer) cho ->
     New.AndObs (New.ChoseSomething (New.ChoiceId idChoice idPer))
                (New.ValueEQ (New.ChoiceValue (New.ChoiceId idChoice idPer)
                                              (New.Constant 0))
                             (New.Constant cho))
   Old.AndObs obs1 obs2 -> New.AndObs (go obs1) (go obs2)
   Old.OrObs obs1 obs2 -> New.OrObs (go obs1) (go obs2)
   Old.NotObs obs1 -> New.NotObs (go obs1)
   Old.ChoseSomething (idChoice, idPer) -> New.ChoseSomething (New.ChoiceId idChoice idPer)
   Old.ValueGE val1 val2 -> New.ValueGE (goVal val1) (goVal val2)
   Old.ValueGT val1 val2 -> New.ValueGT (goVal val1) (goVal val2)
   Old.ValueLT val1 val2 -> New.ValueLT (goVal val1) (goVal val2)
   Old.ValueLE val1 val2 -> New.ValueLE (goVal val1) (goVal val2)
   Old.ValueEQ val1 val2 -> New.ValueEQ (goVal val1) (goVal val2)
   Old.TrueObs -> New.TrueObs
   Old.FalseObs -> New.FalseObs
  where
    go = convertObs ad ce
    goVal = convertVal ad ce

skipChoice :: ActionData -> ConvertEnv -> Old.Contract -> New.Contract
skipChoice ad ce (Old.Null) = refundEverything ad (pays ce)
                                 (sortBy (comparing snd) $ M.toList $ commits ce)
skipChoice ad ce (Old.Choice o c1 c2) = New.If (convertObs ad ce o) (go c1) (go c2)
  where go = skipChoice ad ce
skipChoice ad ce c = flattenQuiescent $ getQuiescent ad ce c

convertAux :: ActionData -> ConvertEnv -> Old.Contract -> New.Contract
convertAux ad ce c = skipChoice ad ce (unfoldChoices ce c)


convert :: Old.Contract -> (New.Contract, ActionData)
convert contract = (convertAux renamings emptyConvertEnv contract, renamings)
  where (renamings, _) = idActionToChoice emptyActionData maxChoices contract
        maxChoices = maxUsedChoices contract


