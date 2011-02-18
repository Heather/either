{-# LANGUAGE FlexibleInstances, FlexibleContexts, UndecidableInstances #-}
module Control.Monad.Trans.Either 
  ( EitherT(..)
  , eitherT
  , hoistEither
  ) where

import Control.Applicative
import Data.Default
import Data.Functor.Bind
import Data.Functor.Plus
import Data.Foldable
import Data.Function (on)
import Data.Traversable
import Data.Monoid
import Data.Semigroup
import Control.Monad.Trans.Class
-- import Control.Monad.Error.Class
import Control.Monad.IO.Class
import Control.Monad.Fix
import Control.Monad (MonadPlus(..), liftM)

newtype EitherT e m a = EitherT { runEitherT :: m (Either e a) }
-- TODO: Data, Typeable

instance Show (m (Either e a)) => Show (EitherT e m a) where
  showsPrec d (EitherT m) = showParen (d > 10) $
    showString "EitherT " . showsPrec 11 m

instance Read (m (Either e a)) => Read (EitherT e m a) where
  readsPrec d r = readParen (d > 10) 
    (\r' -> [ (EitherT m, t) 
            | ("EitherT", s) <- lex r'
            , (m, t) <- readsPrec 11 s]) r

instance Eq (m (Either e a)) => Eq (EitherT e m a) where
  (==) = (==) `on` runEitherT

instance Ord (m (Either e a)) => Ord (EitherT e m a) where
  compare = compare `on` runEitherT

eitherT :: Monad m => (a -> m c) -> (b -> m c) -> EitherT a m b -> m c
eitherT f g (EitherT m) = m >>= \z -> case z of
  Left a -> f a
  Right b -> g b

hoistEither :: Monad m => Either e a -> EitherT e m a
hoistEither = EitherT . return

instance Functor m => Functor (EitherT e m) where
  fmap f = EitherT . fmap (fmap f) . runEitherT 

instance (Functor m, Monad m) => Apply (EitherT e m) where
  EitherT f <.> EitherT v = EitherT $ f >>= \mf -> case mf of
    Left  e -> return (Left e)
    Right k -> v >>= \mv -> case mv of 
      Left  e -> return (Left e)
      Right x -> return (Right (k x))

instance (Functor m, Monad m) => Applicative (EitherT e m) where
  pure a  = EitherT $ return (Right a)
  EitherT f <*> EitherT v = EitherT $ f >>= \mf -> case mf of
    Left  e -> return (Left e)
    Right k -> v >>= \mv -> case mv of 
      Left  e -> return (Left e)
      Right x -> return (Right (k x))

instance Monad m => Semigroup (EitherT e m a) where
  EitherT m <> EitherT n = EitherT $ m >>= \a -> case a of
    Left _ -> n 
    Right r -> return (Right r)

instance (Monad m, Default e) => Monoid (EitherT e m a) where
  mappend = (<>)
  mempty = EitherT $ return $ Left def

instance (Functor m, Monad m) => Alt (EitherT e m) where
  (<!>) = (<>)

instance (Functor m, Monad m, Default e) => Plus (EitherT e m) where
  zero = EitherT $ return $ Left def

instance (Functor m, Monad m, Default e) => Alternative (EitherT e m) where
  empty = zero
  (<|>) = (<!>)

instance (Functor m, Monad m) => Bind (EitherT e m) where
  (>>-) = (>>=)

instance Monad m => Monad (EitherT e m) where
  return a = EitherT $ return (Right a)
  m >>= k  = EitherT $ do
    a <- runEitherT m
    case a of
      Left  l -> return (Left l)
      Right r -> runEitherT (k r)

{-
instance Monad m => MonadError e (EitherT e m) where
  throwError = EitherT . return . Left
  EitherT m `catchError` h = EitherT $ m >>= \a -> case a of
    Left  l -> runEitherT (h l)
    Right r -> return (Right r)
-}

instance (Monad m, Default e) => MonadPlus (EitherT e m) where
  mzero = EitherT $ return $ Left def
  EitherT m `mplus` EitherT n = EitherT $ m >>= \a -> case a of
    Left  _ -> n
    Right r -> return (Right r)

instance MonadFix m => MonadFix (EitherT e m) where
  mfix f = EitherT $ mfix $ \a -> runEitherT $ f $ case a of
    Right r -> r
    _       -> error "empty mfix argument"

instance MonadTrans (EitherT e) where
  lift = EitherT . liftM Right

instance MonadIO m => MonadIO (EitherT e m) where
  liftIO = lift . liftIO

instance Foldable m => Foldable (EitherT e m) where
  foldMap f = foldMap (either mempty f) . runEitherT

instance (Traversable f) => Traversable (EitherT e f) where 
  traverse f (EitherT a) = 
    EitherT <$> traverse (either (pure . Left) (fmap Right . f)) a 
