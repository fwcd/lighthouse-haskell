{-# LANGUAGE OverloadedStrings, RecordWildCards #-}
module Lighthouse.Protocol
    ( FromClientMessage (..), FromServerMessage (..)
    , displayRequest, controllerStreamRequest
    ) where

import Control.Applicative ((<|>))
import Control.Monad ((<=<))
import qualified Data.ByteString.Lazy as BL
import qualified Data.MessagePack as MP
import qualified Data.Text as T
import qualified Data.Vector as V
import Lighthouse.Authentication
import Lighthouse.Display
import Lighthouse.Event
import Lighthouse.Utils.Serializable

-- ======= CLIENT -> SERVER MESSAGES =======

data FromClientMessage a = FromClientRequest { fcReqId :: Int, fcVerb :: T.Text, fcAuthentication :: Authentication, fcPayload :: a }

class MPSerializable a where
    -- | Converts to a MessagePack representation.
    mpSerialize :: a -> MP.Object

instance MPSerializable a => MPSerializable (FromClientMessage a) where
    mpSerialize FromClientRequest {..} = MP.ObjectMap $ V.fromList
        [ (MP.ObjectStr "REID", MP.ObjectInt fcReqId)
        , (MP.ObjectStr "VERB", MP.ObjectStr fcVerb)
        , (MP.ObjectStr "PATH", MP.ObjectArray $ V.fromList (MP.ObjectStr <$> ["user", username, "model"]))
        , (MP.ObjectStr "AUTH", MP.ObjectMap $ V.fromList [(MP.ObjectStr "USER", MP.ObjectStr username), (MP.ObjectStr "TOKEN", MP.ObjectStr token)])
        , (MP.ObjectStr "META", MP.ObjectMap V.empty)
        , (MP.ObjectStr "PAYL", mpSerialize fcPayload)
        ]
        where Authentication {..} = fcAuthentication

instance MPSerializable a => Serializable (FromClientMessage a) where
    serialize = MP.pack . mpSerialize

instance MPSerializable MP.Object where
    mpSerialize = id

instance MPSerializable Display where
    mpSerialize = MP.ObjectBin . BL.toStrict . serialize

-- Creates a display request.
displayRequest :: Authentication -> Display -> FromClientMessage Display
displayRequest auth disp = FromClientRequest
    { fcReqId = 0
    , fcVerb = "PUT"
    , fcAuthentication = auth
    , fcPayload = disp
    }

-- Creates a request for controller stream input.
controllerStreamRequest :: Authentication -> FromClientMessage MP.Object
controllerStreamRequest auth = FromClientRequest
    { fcReqId = -1
    , fcVerb = "STREAM"
    , fcAuthentication = auth
    , fcPayload = MP.ObjectNil
    }

-- ====== SERVER -> CLIENT MESSAGES ======

data FromServerMessage a = FromServerRequest { fsReqId :: Int, fsPayload :: a }
                         | FromServerError { fsError :: T.Text }

class MPDeserializable a where
    -- | Converts from a MessagePack representation.
    mpDeserialize :: MP.Object -> Maybe a

instance MPDeserializable a => MPDeserializable (FromServerMessage a) where
    mpDeserialize (MP.ObjectMap vm) = do
        let m = V.toList vm
        rnum <- MP.fromObject =<< lookup (MP.ObjectStr "RNUM") m
        case rnum :: Int of
            200 -> do
                reqId <- MP.fromObject =<< lookup (MP.ObjectStr "REID") m
                payload <- mpDeserialize =<< lookup (MP.ObjectStr "PAYL") m
                return $ FromServerRequest { fsReqId = reqId, fsPayload = payload }
            _   -> do
                response <- MP.fromObject =<< lookup (MP.ObjectStr "RESPONSE") m
                return $ FromServerError { fsError = response }
    mpDeserialize _ = Nothing

instance MPDeserializable MP.Object where
    mpDeserialize = Just

instance MPDeserializable a => MPDeserializable [a] where
    mpDeserialize (MP.ObjectArray a) = mapM mpDeserialize $ V.toList a
    mpDeserialize _ = Nothing

instance MPDeserializable KeyEvent where
    mpDeserialize (MP.ObjectMap vo) = do
        let o = V.toList vo
        src <- MP.fromObject =<< lookup (MP.ObjectStr "src") o
        key <- MP.fromObject =<< lookup (MP.ObjectStr "key") o <|> lookup (MP.ObjectStr "btn") o
        dwn <- MP.fromObject =<< lookup (MP.ObjectStr "dwn") o
        return $ KeyEvent { eventSource = src, eventKey = key, eventPressed = dwn }
    mpDeserialize _ = Nothing

instance MPDeserializable a => Deserializable (FromServerMessage a) where
    deserialize = mpDeserialize <=< MP.unpack
