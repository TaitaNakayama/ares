import rasterio, math, numpy as np
from rasterio.windows import from_bounds
from rasterio.enums import Resampling
B='https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn/HiRISE/'
R=3396190.
lat,lon=18.4446,77.4509
cx,cy=R*math.radians(lon),R*math.radians(lat)
print('viewpoint x,y',cx,cy)
def crop(name,half,res,out,dtype):
    with rasterio.open('/vsicurl/'+B+name) as d:
        w=from_bounds(cx-half,cy-half,cx+half,cy+half,d.transform).round_offsets().round_lengths()
        n=int(2*half/res)
        arr=d.read(1,window=w,out_shape=(n,n),resampling=Resampling.average if res>d.res[0] else Resampling.nearest)
        prof=d.profile.copy(); prof.update(width=n,height=n,transform=rasterio.transform.from_origin(cx-half,cy+half,res,res),driver='GTiff',tiled=False,compress='deflate',blockxsize=None,blockysize=None)
        for k in ('blockxsize','blockysize'): prof.pop(k,None)
        with rasterio.open(out,'w',**prof) as o: o.write(arr,1)
        print(out,arr.shape,arr.dtype,float(arr.min()),float(arr.max()))
D='/Users/TAITA/Projects/ares/data/raw/'
crop('JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif',2500,1,D+'hirise_dtm_5km_1m.tif','float32')
crop('JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first.tif',1500,0.5,D+'hirise_ortho_3km_0p5m.tif','uint8')
