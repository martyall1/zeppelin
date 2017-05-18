{-# LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Data.SideLoadingSpec (spec) where

import Data.SideLoaded
import Data.Aeson (ToJSON(..), FromJSON(..), Value(..), encode, decode, (.:))
import Data.Aeson.Types (Parser)
import Data.IORef
import Data.Maybe (isJust)
import Data.Proxy
import GHC.Generics (Generic)
import GHC.TypeLits
import System.IO.Unsafe (unsafePerformIO)
import Test.Hspec


spec :: Spec
spec = do

  describe "it should inflate albums" $ do
    it "can serialize dependencies" $ do
      serializedAlbum <- fmap (encode . toJSON) . inflate $ album
      let (mpair :: Maybe (Person, [Photo])) = decode serializedAlbum
      mpair `shouldSatisfy` isJust
      let (Just(o, ps)) = mpair
      o `shouldBe` john
      ps `shouldBe` photos


    it "can do projections" $ do
      serializedAlbum <- inflate $ album
      projectDependency (Proxy @ [Photo]) serializedAlbum `shouldBe` photos
      projectDependency (Proxy @ Person) serializedAlbum `shouldBe` john

--------------------------------------------------------------------------------
-- | Photo

newtype PhotoId = PhotoId Int deriving (Eq, Show, Num, ToJSON, FromJSON)

type instance NamedDependency [Photo] = "photos"

data Photo =
  Photo { photoId :: PhotoId
        , photoCaption :: String
        , photoAlbumId :: AlbumId
        , artistId :: PersonId
        } deriving (Eq, Show, Generic)

instance ToJSON Photo
instance FromJSON Photo

photos :: [Photo]
photos = [Photo 1 "At the Beach" 1 1, Photo 2 "In the Mountains" 1 1]

photos' :: IORef [Photo]
photos' = unsafePerformIO $ newIORef photos
{-# NOINLINE photos #-}

instance Inflatable IO [PhotoId] [Photo] where
  inflator = const $ readIORef photos'

-- | Person

newtype PersonId = PersonId Int deriving (Eq, Show, Num, ToJSON, FromJSON)

type instance NamedDependency Person = "person"

data Person =
  Person { personId :: PersonId
         , personName :: String
         } deriving (Eq, Show, Generic)

instance ToJSON Person
instance FromJSON Person

john :: Person
john =  Person 1 "John"

john' :: IORef Person
john' = unsafePerformIO $ newIORef john
{-# NOINLINE john #-}

instance Inflatable IO PersonId Person where
  inflator = const $ readIORef john'

-- | Albums

newtype AlbumId = AlbumId Int deriving (Eq, Show, Num, ToJSON, FromJSON)

data Album =
  Album { albumId :: AlbumId
        , albumName :: String
        , albumOwner :: PersonId
        , albumPhotos :: [PhotoId]
        } deriving (Eq, Show, Generic)

instance ToJSON Album

instance HasDependencies IO Album [Person, [Photo]] where
  type DependencyBase Album = [PersonId, [PhotoId]]
  getDependencies (Album _ _ owner pIds) = owner &: pIds &: NilDeps

album :: Album
album = Album 1 "Vacations" 1 [1,2]

--------------------------------------------------------------------------------

instance {-# OVERLAPPING #-} FromJSON (Person, [Photo]) where
  parseJSON (Object o) =
    (,) <$> ((o .: "dependencies") >>= (.: "person"))
        <*> ((o .: "dependencies") >>= (.: "photos"))
  parseJSON invalid = fail "could not parse dependencies"

