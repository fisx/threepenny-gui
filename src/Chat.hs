{-# LANGUAGE CPP, PackageImports #-}
{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}

import Control.Concurrent
import qualified Control.Concurrent.Chan as Chan
import Control.Exception
import Control.Monad
import Data.Functor
import Data.List.Extra
import Data.Time
import Data.IORef
import Prelude hiding (catch)

import Control.Monad.Trans.Reader as Reader
import Control.Monad.IO.Class

#ifdef CABAL
import qualified "threepenny-gui" Graphics.UI.Threepenny as UI
import "threepenny-gui" Graphics.UI.Threepenny.Core hiding (text)
#else
import qualified Graphics.UI.Threepenny as UI
import Graphics.UI.Threepenny.Core hiding (text)
#endif
import Paths

{-----------------------------------------------------------------------------
    Chat
------------------------------------------------------------------------------}

main :: IO ()
main = do
    static   <- getStaticDir
    messages <- Chan.newChan
    startGUI Config
        { tpPort       = 10000
        , tpCustomHTML = Just "chat.html"
        , tpStatic     = static
        } $ setup messages

type Message = (UTCTime, String, String)

setup :: Chan Message -> Window -> IO ()
setup globalMsgs window = do
    msgs <- Chan.dupChan globalMsgs

    return window # set title "Chat"
    
    (nickRef, nickname) <- mkNickname
    messageArea         <- mkMessageArea msgs nickRef

    getBody window #+
        [ UI.div #. "header"   #+ [string "Threepenny Chat"]
        , UI.div #. "gradient"
        , viewSource
        , element nickname
        , element messageArea
        ]
    
    messageReceiver <- forkIO $ receiveMessages window msgs messageArea

    on UI.disconnect window $ const $ do
        putStrLn "Disconnected!"
        killThread messageReceiver
        now   <- getCurrentTime
        nick  <- readIORef nickRef
        Chan.writeChan msgs (now,nick,"( left the conversation )")


receiveMessages w msgs messageArea = do
    messages <- Chan.getChanContents msgs
    forM_ messages $ \msg -> do
        atomic w $ do
          element messageArea #+ [mkMessage msg]
          UI.scrollToBottom messageArea

mkMessageArea :: Chan Message -> IORef String -> IO Element
mkMessageArea msgs nickname = do
    input <- UI.textarea #. "send-textarea"
    
    on UI.sendValue input $ (. trim) $ \content -> do
        when (not (null content)) $ do
            now  <- getCurrentTime
            nick <- readIORef nickname
            element input # set value ""
            when (not (null nick)) $
                Chan.writeChan msgs (now,nick,content)

    UI.div #. "message-area" #+ [UI.div #. "send-area" #+ [element input]]


mkNickname :: IO (IORef String, Element)
mkNickname = do
    input  <- UI.input #. "name-input"
    el     <- UI.div   #. "name-area"  #+
                [ UI.span  #. "name-label" #+ [string "Your name "]
                , element input
                ]
    UI.setFocus input
    
    nick <- newIORef ""
    on UI.keyup input $ \_ -> writeIORef nick . trim =<< get value input
    return (nick,el)

mkMessage :: Message -> IO Element
mkMessage (timestamp, nick, content) =
    UI.div #. "message" #+
        [ UI.div #. "timestamp" #+ [string $ show timestamp]
        , UI.div #. "name"      #+ [string $ nick ++ " says:"]
        , UI.div #. "content"   #+ [string content]
        ]

viewSource :: IO Element
viewSource =
    UI.anchor #. "view-source" # set UI.href url #+ [string "View source code"]
    where
    url = "https://github.com/HeinrichApfelmus/threepenny-gui/blob/master/src/Chat.hs"
