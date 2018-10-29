module GenSemantics where

import Data.Set (Set)
import qualified Data.Set as S
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M

import Semantics
import Test.QuickCheck

arbitraryMoneyAux :: Int -> Gen Money
arbitraryMoneyAux s
 | s > 0 = oneof [(AvailableMoney . IdentCC) <$> arbitrary
                 ,(AddMoney <$> arbitraryMoneyAux (s - 1)) <*> arbitraryMoneyAux (s - 1)
                 ,ConstMoney <$> arbitrary
                 ,(MoneyFromChoice . IdentChoice) <$> arbitrary <*> arbitrary <*> arbitraryMoneyAux (s - 1)]
 | s == 0 = oneof [(AvailableMoney . IdentCC) <$> arbitrary
                  ,ConstMoney <$> arbitrary]
 | otherwise = error "Negative size in arbitraryMoney"
 
arbitraryMoney :: Gen Money
arbitraryMoney = sized arbitraryMoneyAux

arbitraryObservationAux :: Int -> Gen Observation
arbitraryObservationAux s
 | s > 0 = oneof [BelowTimeout <$> arbitrary
                 ,AndObs <$> arbitraryObservationAux (s - 1) <*> arbitraryObservationAux (s - 1) 
                 ,OrObs <$> arbitraryObservationAux (s - 1) <*> arbitraryObservationAux (s - 1)
                 ,NotObs <$> arbitraryObservationAux (s - 1)  
                 ,(PersonChoseThis . IdentChoice) <$> arbitrary <*> arbitrary <*>  arbitrary
                 ,(PersonChoseSomething . IdentChoice) <$> arbitrary <*> arbitrary
                 ,ValueGE <$> arbitraryMoneyAux (s - 1) <*> arbitraryMoneyAux (s - 1)
                 ,pure TrueObs,pure FalseObs]
 | s == 0 = oneof [BelowTimeout <$> arbitrary
                  ,(PersonChoseThis . IdentChoice) <$> arbitrary <*> arbitrary <*> arbitrary
                  ,(PersonChoseSomething . IdentChoice) <$> arbitrary <*> arbitrary
                  ,pure TrueObs,pure FalseObs]
 | otherwise = error "Negative size in arbitraryObservation"


arbitraryObservation :: Gen Observation
arbitraryObservation = sized arbitraryObservationAux

arbitraryContractAux :: Int -> Gen Contract
arbitraryContractAux s
 | s > 0 = oneof [pure Null
                 ,(CommitCash . IdentCC) <$> arbitrary <*> arbitrary <*> arbitraryMoneyAux (s - 1) <*> arbitrary <*> arbitrary <*> arbitraryContractAux (s - 1) <*> arbitraryContractAux (s - 1) 
                 ,(RedeemCC . IdentCC) <$> arbitrary <*> arbitraryContractAux (s - 1)
                 ,(Pay . IdentPay) <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitraryMoneyAux (s - 1) <*> arbitrary <*> arbitraryContractAux (s - 1)
                 ,Both <$> arbitraryContractAux (s - 1) <*> arbitraryContractAux (s - 1)
                 ,Choice <$> arbitraryObservationAux (s - 1) <*> arbitraryContractAux (s - 1) <*> arbitraryContractAux (s - 1)
                 ,When <$> arbitraryObservationAux (s - 1) <*> arbitrary <*> arbitraryContractAux (s - 1) <*> arbitraryContractAux (s - 1)]
 | s == 0 = oneof [pure Null]
 | otherwise = error "Negative size in arbitraryObservation"

arbitraryContract :: Gen Contract
arbitraryContract = sized arbitraryContractAux

arbitraryCC :: Gen CC
arbitraryCC = (CC . IdentCC) <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

arbitraryRC :: Gen RC
arbitraryRC = (RC . IdentCC) <$> arbitrary <*> arbitrary <*> arbitrary

arbitraryRPEntry :: Gen ((IdentPay, Person), Cash)
arbitraryRPEntry = (\x y z -> ((IdentPay x, y), z)) <$> arbitrary <*> arbitrary <*> arbitrary

arbitraryICEntry :: Gen ((IdentChoice, Person), ConcreteChoice)
arbitraryICEntry = (\x y z -> ((IdentChoice x, y), z)) <$> arbitrary <*> arbitrary <*> arbitrary

arbitraryInputAux :: Int -> Gen Input
arbitraryInputAux s = (\w x y z -> Input (S.fromList w) (S.fromList x) (M.fromList y) (M.fromList z))
                      <$> vectorOf s arbitraryCC <*> vectorOf s arbitraryRC <*> vectorOf s arbitraryRPEntry <*> vectorOf s arbitraryICEntry

arbitraryInput :: Gen Input
arbitraryInput = sized arbitraryInputAux


