"""Mars24 (Allison & McEwen 2000) solar position. Public-domain-style reimplementation from the
NASA GISS algorithm page formulas (https://www.giss.nasa.gov/tools/mars24/help/algorithm.html)."""
import math
from datetime import datetime, timezone

# TAI-UTC (s) since 2017-01-01 = 37 (no leap seconds added through 2026 per IERS bulletins; verify)
TT_MINUS_UTC = 37 + 32.184
_PERT = [(0.0071,2.2353,49.409),(0.0057,2.7543,168.173),(0.0039,1.1177,191.837),
         (0.0037,15.7866,21.736),(0.0021,2.1354,15.704),(0.0020,2.4694,95.528),(0.0018,32.8493,49.095)]
d2r = math.radians

def jd_tt_from_unix(unix_s, tt_utc=TT_MINUS_UTC):
    return 2440587.5 + unix_s/86400.0 + tt_utc/86400.0

def mars24(jd_tt, lat_deg, lon_east_deg):
    dt = jd_tt - 2451545.0
    M = 19.3871 + 0.52402073*dt
    a_fms = 270.3871 + 0.524038496*dt
    pbs = sum(A*math.cos(d2r(0.985626*dt/tau + ph)) for A,tau,ph in _PERT)
    nu_m = ((10.691+3.0e-7*dt)*math.sin(d2r(M)) + 0.623*math.sin(d2r(2*M)) + 0.050*math.sin(d2r(3*M))
            + 0.005*math.sin(d2r(4*M)) + 0.0005*math.sin(d2r(5*M)) + pbs)
    Ls = (a_fms + nu_m) % 360
    eot = 2.861*math.sin(d2r(2*Ls)) - 0.071*math.sin(d2r(4*Ls)) + 0.002*math.sin(d2r(6*Ls)) - nu_m  # deg
    mst = (24*((jd_tt - 2451549.5)/1.0274912517 + 44796.0 - 0.0009626)) % 24
    lam_w = (-lon_east_deg) % 360
    lmst = (mst - lam_w/15) % 24
    ltst = (lmst + eot/15) % 24
    dec = math.degrees(math.asin(0.42565*math.sin(d2r(Ls)))) + 0.25*math.sin(d2r(Ls))
    lam_s = 15*mst + eot + 180            # subsolar longitude, deg West
    H = d2r(lam_w - lam_s)
    phi = d2r(lat_deg); de = d2r(dec)
    cosZ = math.sin(de)*math.sin(phi) + math.cos(de)*math.cos(phi)*math.cos(H)
    elev = 90 - math.degrees(math.acos(max(-1,min(1,cosZ))))
    az = math.degrees(math.atan2(math.sin(H), math.cos(phi)*math.tan(de) - math.sin(phi)*math.cos(H))) % 360
    return dict(Ls=Ls, ltst=ltst, dec=dec, elev=elev, az=az, dt=dt, mst=mst)

if __name__ == "__main__":
    # GISS check 1: 2000-01-06 00:00 UTC (TT-UTC = 64.184 s then)
    u = datetime(2000,1,6,tzinfo=timezone.utc).timestamp()
    r = mars24(jd_tt_from_unix(u, 64.184), 0, 0)
    print("check1 dt=%.5f (4.50074) Ls=%.5f (277.18758) MST=%.4f h (23:59:39=23.9942)" % (r['dt'], r['Ls'], r['mst']))
    now = datetime.now(timezone.utc).timestamp()
    r = mars24(jd_tt_from_unix(now), 18.4446, 77.4509)
    print("Jezero now:", {k: round(v,3) for k,v in r.items()})
    # sweep one sol at Jezero
    base = now
    for i in range(0, 25, 2):
        r = mars24(jd_tt_from_unix(base + i*3600), 18.4446, 77.4509)
        print("+%2dh LTST=%5.2f elev=%6.1f az=%6.1f Ls=%.1f" % (i, r['ltst'], r['elev'], r['az'], r['Ls']))
