{-# LANGUAGE TypeFamilies #-}

module Propellor.Types.Container where

-- | A value that can be bound between the host and a container.
--
-- For example, a Bound Port is a Port on the container that is bound to
-- a Port on the host.
data Bound v = Bound
	{ hostSide :: v
	, containerSide :: v
	}

-- | Create a Bound value, from two different values for the host and
-- container.
--
-- For example, @Port 8080 -<- Port 80@ means that port 8080 on the host
-- is bound to port 80 from the container.
(-<-) :: (hostv ~ v, containerv ~ v) => hostv -> containerv -> Bound v
(-<-) hostv containerv = Bound hostv containerv

-- | Flipped version of -<- with the container value first and host value
-- second.
(->-) :: (containerv ~ v, hostv ~ v) => hostv -> containerv -> Bound v
(->-) containerv hostv = Bound hostv containerv

-- | Create a Bound value, that is the same on both the host and container.
same :: v -> Bound v
same v = Bound v v

