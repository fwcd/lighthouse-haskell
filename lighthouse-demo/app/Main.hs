module Main where

import qualified Codec.Picture as P
import Control.Monad (void)
import Control.Monad.Except (liftEither)
import Control.Monad.Trans (lift, liftIO)
import Control.Monad.Trans.Except
import qualified Data.Text as T
import Lighthouse.Authentication
import Lighthouse.Connection
import Lighthouse.Display
import Lighthouse.Utils.Color
import Lighthouse.Utils.General (liftMaybe)
import System.Environment (getArgs, getEnv)
import System.Random

-- | Renders a single image to the lighthouse.
app :: String -> LighthouseIO ()
app imagePath = do
    res <- runExceptT $ do
        dimg <- liftEither =<< liftIO (P.readPng imagePath)
        d <- liftEither $ dynImgToDisplay dimg
        lift $ sendDisplay d
        
    case res of
        Left e -> liftIO $ putStrLn e
        _ -> return ()
    
    sendClose

dynImgToDisplay :: P.DynamicImage -> Either String Display
dynImgToDisplay dimg = case dimg of
    P.ImageRGB8 img -> Right $ imgToDisplay img $ \(P.PixelRGB8 r g b) -> Color (fromIntegral r) (fromIntegral g) (fromIntegral b)
    P.ImageRGBA8 img -> Right $ imgToDisplay img $ \(P.PixelRGBA8 r g b _) -> Color (fromIntegral r) (fromIntegral g) (fromIntegral b)
    _ -> Left "Unrecognized PNG format"

imgToDisplay :: P.Pixel a => P.Image a -> (a -> Color) -> Display
imgToDisplay img pxToColor = Display $ (\y -> Row $ (\x -> pxToColor $ P.pixelAt img x y) <$> [0..width - 1]) <$> [0..height - 1]
    where width = P.imageWidth img
          height = P.imageHeight img

main :: IO ()
main = do
    -- Fetch credentials from env vars
    username <- T.pack <$> getEnv "LIGHTHOUSE_USERNAME"
    token    <- T.pack <$> getEnv "LIGHTHOUSE_TOKEN"
    let auth = Authentication { username = username, token = token }

    -- Render image to lighthouse
    args <- getArgs
    case args of
        [imagePath] -> runLighthouseIO (app imagePath) auth
        _           -> putStrLn "Arguments: [path to png image]"
