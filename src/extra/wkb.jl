
@enum wkbGeometryType begin
  wkbUnknown = 0
  wkbPoint = 1
  wkbLineString = 2
  wkbPolygon = 3
  wkbMultiPoint = 4
  wkbMultiLineString = 5
  wkbMultiPolygon = 6
  wkbGeometryCollection = 7
  wkbCircularString = 8
  wkbCompoundCurve = 9
  wkbCurvePolygon = 10
  wkbMultiCurve = 11
  wkbMultiSurface = 12
  wkbCurve = 13
  wkbSurface = 14

  wkbNone = 100 # pure attribute records
  wkbLinearRing = 101

  # ISO SQL/MM Part 3: Spatial
  # Z-aware types
  wkbPointZ = 1001
  wkbLineStringZ = 1002
  wkbPolygonZ = 1003
  wkbMultiPointZ = 1004
  wkbMultiLineStringZ = 1005
  wkbMultiPolygonZ = 1006
  wkbGeometryCollectionZ = 1007
  wkbCircularStringZ = 1008
  wkbCompoundCurveZ = 1009
  wkbCurvePolygonZ = 1010
  wkbMultiCurveZ = 1011
  wkbMultiSurfaceZ = 1012
  wkbCurveZ = 1013
  wkbSurfaceZ = 1014

  # ISO SQL/MM Part 3.
  # M-aware types
  wkbPointM = 2001
  wkbLineStringM = 2002
  wkbPolygonM = 2003
  wkbMultiPointM = 2004
  wkbMultiLineStringM = 2005
  wkbMultiPolygonM = 2006
  wkbGeometryCollectionM = 2007
  wkbCircularStringM = 2008
  wkbCompoundCurveM = 2009
  wkbCurvePolygonM = 2010
  wkbMultiCurveM = 2011
  wkbMultiSurfaceM = 2012
  wkbCurveM = 2013
  wkbSurfaceM = 2014

  # ISO SQL/MM Part 3.
  # ZM-aware types
  wkbPointZM = 3001
  wkbLineStringZM = 3002
  wkbPolygonZM = 3003
  wkbMultiPointZM = 3004
  wkbMultiLineStringZM = 3005
  wkbMultiPolygonZM = 3006
  wkbGeometryCollectionZM = 3007
  wkbCircularStringZM = 3008
  wkbCompoundCurveZM = 3009
  wkbCurvePolygonZM = 3010
  wkbMultiCurveZM = 3011
  wkbMultiSurfaceZM = 3012
  wkbCurveZM = 3013
  wkbSurfaceZM = 3014

  # 2.5D extension as per 99-402
  # https://lists.osgeo.org/pipermail/postgis-devel/2004-December/000702.html
  wkbPoint25D = 0x80000001
  wkbLineString25D = 0x80000002
  wkbPolygon25D = 0x80000003
  wkbMultiPoint25D = 0x80000004
  wkbMultiLineString25D = 0x80000005
  wkbMultiPolygon25D = 0x80000006
  wkbGeometryCollection25D = 0x80000007
end
