#!/usr/bin/env python3
import argparse, csv, hashlib, json, math, xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
import numpy as np
from scipy.optimize import minimize
from scipy.special import logsumexp

EPS=1e-12

def wrap(a):
    return (np.asarray(a)+np.pi)%(2*np.pi)-np.pi

def sha256(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for c in iter(lambda:f.read(1<<20), b""): h.update(c)
    return h.hexdigest()

def sd(x):
    x=np.asarray(x,float)
    return float(np.std(x,ddof=1)) if len(x)>1 else 0.0

def rms(x):
    x=np.asarray(x,float)
    return float(np.sqrt(np.mean(x*x))) if len(x) else 0.0

def nlogpdf(x,mu,s):
    s=np.maximum(np.asarray(s,float),1e-9)
    return -0.5*((x-mu)/s)**2-np.log(s)-0.5*np.log(2*np.pi)

@dataclass
class Track:
    tid:str
    frame:np.ndarray
    x:np.ndarray
    y:np.ndarray
    def disp(self): return np.column_stack((np.diff(self.x),np.diff(self.y)))
    def steps(self): return np.linalg.norm(self.disp(),axis=1)
    def turns(self):
        d=self.disp()
        h=np.arctan2(d[:,1],d[:,0])
        return wrap(np.diff(h))

def attr(el,*names):
    for n in names:
        if n in el.attrib: return el.attrib[n]
    return None

def infer_dt(root):
    for el in root.iter():
        for k in ("timeinterval","TIME_INTERVAL","frameInterval","FRAME_INTERVAL"):
            if k in el.attrib:
                try:
                    v=float(el.attrib[k])
                    if v>0:return v
                except: pass
    return None

def parse_trackmate(path,min_spots=4):
    """
    Supports both:
      1) the compact TrackMate export used in Le Berre et al.:
         <Tracks ...><particle nSpots="..."><detection t="..." x="..." y="..."/>
      2) standard TrackMate Model/AllSpots/AllTracks XML with Spot/Edge elements.
    """
    root=ET.parse(path).getroot()
    tracks=[]

    # ---- Compact TrackMate trajectory export: Tracks/particle/detection ----
    particles=[el for el in root.iter() if el.tag.split("}")[-1]=="particle"]
    if particles:
        for i,p in enumerate(particles):
            rows=[]
            for d in list(p):
                if d.tag.split("}")[-1]!="detection":
                    continue
                ts=attr(d,"t","T","frame","FRAME")
                xs=attr(d,"x","X","POSITION_X")
                ys=attr(d,"y","Y","POSITION_Y")
                if None in (ts,xs,ys):
                    continue
                try:
                    t=int(round(float(ts))); x=float(xs); y=float(ys)
                except ValueError:
                    continue
                if np.isfinite(x) and np.isfinite(y):
                    rows.append((x,y,t))

            if len(rows)<min_spots:
                continue
            rows.sort(key=lambda z:z[2])
            a=np.asarray(rows,float)
            f=a[:,2].astype(int)

            # Preserve only complete, consecutively sampled trajectories.
            if np.any(np.diff(f)!=1):
                continue

            tid=attr(p,"id","ID","name","TRACK_ID") or str(i)
            tracks.append(Track(str(tid),f,a[:,0],a[:,1]))

        if not tracks:
            raise RuntimeError("Compact TrackMate XML detected, but no eligible particle trajectories were found.")
        return tracks,infer_dt(root)

    # ---- Standard TrackMate XML: Spot IDs linked by Track/Edge elements ----
    spots={}
    for el in root.iter():
        if el.tag.split("}")[-1]!="Spot":
            continue
        sid=attr(el,"ID","id")
        xs=attr(el,"POSITION_X","x","X")
        ys=attr(el,"POSITION_Y","y","Y")
        fr=attr(el,"FRAME","frame")
        if None in (sid,xs,ys,fr):
            continue
        try:
            spots[sid]=(float(xs),float(ys),int(round(float(fr))))
        except ValueError:
            pass

    auto=0
    for tr in root.iter():
        if tr.tag.split("}")[-1]!="Track":
            continue
        ids=set()
        for e in list(tr):
            if e.tag.split("}")[-1]!="Edge":
                continue
            s=attr(e,"SPOT_SOURCE_ID","SOURCE_ID","source")
            t=attr(e,"SPOT_TARGET_ID","TARGET_ID","target")
            if s is not None:
                ids.add(s)
            if t is not None:
                ids.add(t)
        rows=[spots[i] for i in ids if i in spots]
        if len(rows)<min_spots:
            continue
        rows.sort(key=lambda z:z[2])
        a=np.asarray(rows,float)
        f=a[:,2].astype(int)
        if np.any(np.diff(f)!=1):
            continue
        tid=attr(tr,"TRACK_ID","name","TRACK_NAME") or str(auto)
        auto+=1
        tracks.append(Track(str(tid),f,a[:,0],a[:,1]))

    if not tracks:
        raise RuntimeError("No eligible TrackMate tracks found")
    return tracks,infer_dt(root)

def flatten(tracks):
    steps=[t.steps() for t in tracks]; turns=[t.turns() for t in tracks]; vel=[t.disp() for t in tracks]
    return steps,turns,vel,np.concatenate(steps),np.concatenate(turns),np.vstack(vel)

def fit_base(all_s,all_a):
    return float(np.mean(all_s)),sd(all_s),rms(all_a)

def fit_turn_ar1(turns):
    x=[]; y=[]
    for a in turns:
        if len(a)>=2: x.append(a[:-1]); y.append(a[1:])
    if not x:return 0.0
    x=np.concatenate(x); y=np.concatenate(y)
    r=float(np.dot(x,y)/max(np.dot(x,x),EPS))
    return float(np.clip(r,-.999,.999))

def fit_ou(vel):
    x=[]; y=[]
    for v in vel:
        if len(v)>=2:x.append(v[:-1]); y.append(v[1:])
    x=np.vstack(x); y=np.vstack(y)
    rho=float(np.sum(x*y)/max(np.sum(x*x),EPS)); rho=float(np.clip(rho,0,.999))
    resid=y-rho*x
    return rho,float(np.sqrt(np.mean(resid*resid)))

def step_turn_pairs(steps,turns):
    return np.concatenate([s[1:] for s,a in zip(steps,turns) if len(a)]),np.concatenate([a for a in turns if len(a)])

def fit_speed_turn(steps,turns,variant):
    s,a=step_turn_pairs(steps,turns)
    mu=float(np.mean(np.concatenate(steps))); sds=sd(np.concatenate(steps)); ta=max(rms(a),1e-6)
    if sds<=1e-10: raise RuntimeError("CAN-SPEED-TURN not identifiable: step SD ~ 0")
    if variant=="RUN2":
        def obj(z):
            sig=math.exp(z[0]); c=z[1]; floor=math.exp(z[2])
            scale=np.maximum(floor,sig+c*(s-mu))
            return -float(np.sum(nlogpdf(a,0,scale)))
        r=minimize(obj,[math.log(ta),0,math.log(max(ta*.1,1e-4))],method="L-BFGS-B")
        return dict(formula="RUN2_additive_rad",step_mean_um=mu,step_sd_um=sds,turn_sd_rad=math.exp(r.x[0]),coupling=float(r.x[1]),turn_scale_floor=math.exp(r.x[2]))
    def obj(z):
        sig=math.exp(z[0]); c=z[1]; floor=1e-4+.9999/(1+math.exp(-z[2]))
        scale=sig*np.maximum(floor,1+c*(mu-s)/max(mu,EPS))
        return -float(np.sum(nlogpdf(a,0,scale)))
    r=minimize(obj,[math.log(ta),0,-2],method="L-BFGS-B")
    return dict(formula="RUN3_multiplicative",step_mean_um=mu,step_sd_um=sds,turn_sd_rad=math.exp(r.x[0]),coupling=float(r.x[1]),turn_scale_floor=1e-4+.9999/(1+math.exp(-r.x[2])))

def fb(le,q):
    q=np.clip(q,1e-8,1-1e-8); lt=np.log([[1-q,q],[q,1-q]])
    la=np.empty_like(le); la[0]=np.log([.5,.5])+le[0]
    for i in range(1,len(le)): la[i]=le[i]+logsumexp(la[i-1][:,None]+lt,axis=0)
    return float(logsumexp(la[-1]))

def fit_switch_turn(turns,all_s):
    seq=[a for a in turns if len(a)>=2]; base=max(rms(np.concatenate(seq)),1e-4)
    def obj(z):
        s1,s2=math.exp(z[0]),math.exp(z[1]); q=1/(1+math.exp(-z[2]))
        return -sum(fb(np.column_stack((nlogpdf(a,0,s1),nlogpdf(a,0,s2))),q) for a in seq)
    r=minimize(obj,[math.log(base*.5),math.log(base*1.5),-2.2],method="L-BFGS-B")
    s1,s2=sorted((math.exp(r.x[0]),math.exp(r.x[1]))); q=1/(1+math.exp(-r.x[2]))
    return dict(switch_prob=q,run_turn_sd_rad=s1,reorient_turn_sd_rad=s2,step_mean_um=float(np.mean(all_s)),step_sd_um=sd(all_s),transition_form="symmetric_flip")

def fit_switch_speed(steps,all_a):
    seq=[s for s in steps if len(s)>=2]; alls=np.concatenate(seq); mu0=float(np.mean(alls)); sd0=max(sd(alls),mu0*1e-3)
    def obj(z):
        mu,ss=math.exp(z[0]),math.exp(z[1]); rr=1/(1+math.exp(-z[2])); q=1/(1+math.exp(-z[3]))
        return -sum(fb(np.column_stack((nlogpdf(s,mu,ss),nlogpdf(s,rr*mu,max(rr*ss,1e-8)))),q) for s in seq)
    r=minimize(obj,[math.log(mu0*1.15),math.log(sd0),0,-2.2],method="L-BFGS-B")
    mu,ss=math.exp(r.x[0]),math.exp(r.x[1]); rr=1/(1+math.exp(-r.x[2])); q=1/(1+math.exp(-r.x[3]))
    return dict(switch_prob=q,slow_factor=rr,step_min_um=0.0,step_mean_um=mu,step_sd_um=ss,turn_sd_rad=rms(all_a),transition_form="symmetric_flip")

def fit_switch_pause(steps,all_a):
    # Fit state persistence from a two-Gaussian HMM on log(step+eps); nuisance emissions are not exported.
    seq=[s for s in steps if len(s)>=2]; alls=np.concatenate(seq); eps=max(np.quantile(alls[alls>0],.001)*.1 if np.any(alls>0) else 1e-9,1e-9)
    ys=[np.log(s+eps) for s in seq]; ay=np.concatenate(ys); q25,q75=np.quantile(ay,[.25,.75]); s0=max(sd(ay),.1)
    def obj(z):
        m0,m1=z[0],z[1]; a0,a1=math.exp(z[2]),math.exp(z[3]); p00=1/(1+math.exp(-z[4])); p11=1/(1+math.exp(-z[5]))
        T=np.log(np.clip([[p00,1-p00],[1-p11,p11]],1e-12,1))
        tot=0
        for y in ys:
            le=np.column_stack((nlogpdf(y,m0,a0),nlogpdf(y,m1,a1)))
            la=np.empty_like(le); la[0]=np.log([.5,.5])+le[0]
            for i in range(1,len(y)): la[i]=le[i]+logsumexp(la[i-1][:,None]+T,axis=0)
            tot+=logsumexp(la[-1])
        return -float(tot)
    r=minimize(obj,[q25,q75,math.log(s0*.7),math.log(s0*.7),2,2],method="L-BFGS-B")
    m0,m1=r.x[:2]; p00=1/(1+math.exp(-r.x[4])); p11=1/(1+math.exp(-r.x[5]))
    pp,pm=(p00,p11) if m0<m1 else (p11,p00)
    return dict(p_move_stay=pm,p_pause_stay=pp,step_mean_um=float(np.mean(alls)),step_sd_um=sd(alls),turn_sd_rad=rms(all_a),pause_emission="exact_zero")

def fit_het(steps,all_a,variant):
    alls=np.concatenate(steps); mu=float(np.mean(alls)); means=np.array([np.mean(s) for s in steps])
    if variant=="RUN2":
        return dict(formula="RUN2_additive_fixed",step_mean_um=mu,hetero_sd_um=sd(means),turn_sd_rad=rms(all_a))
    num=den=0
    for s in steps:
        if len(s)>1:num+=float(np.sum((s-np.mean(s))**2)); den+=len(s)-1
    within=math.sqrt(num/den) if den else 0
    return dict(formula="RUN3_multiplicative",step_mean_um=mu,step_sd_um=within,turn_sd_rad=rms(all_a),hetero_cv=sd(means)/max(mu,EPS),hetero_multiplier_min=1e-6,step_min_um=0.0)

def fit_reversal(all_s,all_a):
    d0=np.abs(wrap(all_a)); dpi=np.abs(wrap(np.abs(all_a)-np.pi)); base=max(np.median(d0)/.6745,1e-3)
    def obj(z):
        sig=math.exp(z[0]); p=1/(1+math.exp(-z[1]))
        L=np.column_stack((math.log(max(1-p,1e-12))+nlogpdf(d0,0,sig),math.log(max(p,1e-12))+nlogpdf(dpi,0,sig)))
        return -float(np.sum(logsumexp(L,axis=1)))
    r=minimize(obj,[math.log(base),-3],method="L-BFGS-B"); p=1/(1+math.exp(-r.x[1]))
    return dict(step_mean_um=float(np.mean(all_s)),step_sd_um=sd(all_s),turn_sd_rad=math.exp(r.x[0]),reversal_prob=p,reversal_angle_rad=np.pi)

def write_empirical(tracks, local, whole):
    """Write empirical artifacts in the exact line-oriented formats expected
    by portfolio_plugin.ml.

    CAN-EMP-LOCAL:
        one line per adjacent displacement pair: step_um,turn_rad
        where step_um = norm(b) and turn_rad = angle(b)-angle(a).

    CAN-EMP-WHOLE:
        one complete empirical displacement sequence per line:
        dx,dy dx,dy dx,dy ...

    No headers are written because the OCaml plugin parses every non-empty,
    non-comment line as scientific data.
    """
    with open(local, "w") as f:
        for t in tracks:
            v = t.disp()
            if len(v) < 2:
                continue
            h = np.arctan2(v[:, 1], v[:, 0])
            for i in range(len(v) - 1):
                step_um = float(np.hypot(v[i + 1, 0], v[i + 1, 1]))
                turn_rad = float(wrap(h[i + 1] - h[i]))
                f.write(f"{step_um:.17g},{turn_rad:.17g}\n")

    with open(whole, "w") as f:
        for t in tracks:
            v = t.disp()
            if len(v) == 0:
                continue
            f.write(" ".join(f"{float(dx):.17g},{float(dy):.17g}" for dx, dy in v) + "\n")

def q(v):
    if isinstance(v,str): return '"'+v.replace("\\","\\\\").replace('"','\\"')+'"'
    if isinstance(v,bool): return "true" if v else "false"
    return repr(float(v)) if isinstance(v,(float,np.floating)) else str(v)

def write_toml(params,dt,path):
    L=['schema_version = "canonical-portfolio-parameters-1.0"',"","[common]",f"dt_sec = {dt!r}","agents = 1",'initial_position = "domain_center"','initial_heading = "uniform_0_2pi"','boundary = "specular_reflect_recursive"',"record_initial_frame = true",""]
    for m,d in params.items():
        L.append(f"[model.{m}]")
        for k,v in d.items(): L.append(f"{k} = {q(v)}")
        L.append("")
    Path(path).write_text("\n".join(L))

def main():
    ap=argparse.ArgumentParser(description="Fit all 13 reconciled canonical zoospore models from TrackMate XML.")
    ap.add_argument("xml",type=Path); ap.add_argument("--out",type=Path,default=Path("canonical_fit"))
    ap.add_argument("--dt-sec",type=float,default=None); ap.add_argument("--min-spots",type=int,default=4)
    ap.add_argument("--speed-turn-variant",choices=["RUN2","RUN3"],default="RUN2")
    ap.add_argument("--heterogeneity-variant",choices=["RUN2","RUN3"],default="RUN3")
    ap.add_argument("--orientation-policy",choices=["laboratory","random_rotation"],default="random_rotation")
    ap.add_argument("--post-sequence-policy",choices=["stop","zero_steps","reject_length_mismatch"],default="reject_length_mismatch")
    a=ap.parse_args(); a.out.mkdir(parents=True,exist_ok=True)
    tracks,xdt=parse_trackmate(a.xml,a.min_spots); dt=a.dt_sec or xdt
    if dt is None: raise RuntimeError("Frame interval not found; use --dt-sec")
    steps,turns,vel,alls,alla,allv=flatten(tracks); mu,sds,tsa=fit_base(alls,alla)
    local=a.out/"empirical_local_transitions.txt"; whole=a.out/"empirical_whole_trajectories.txt"; write_empirical(tracks,local,whole)
    rho,noise=fit_ou(vel)
    P={
      "CAN-IID":dict(step_mean_um=mu,step_sd_um=sds),
      "CAN-BALLISTIC":dict(step_mean_um=mu,step_sd_um=sds),
      "CAN-PCRW":dict(step_mean_um=mu,step_sd_um=sds,turn_sd_rad=tsa,innovation_law="gaussian"),
      "CAN-TURN-AR1":dict(step_mean_um=mu,step_sd_um=sds,turn_sd_rad=tsa,turn_memory=fit_turn_ar1(turns),initial_turn="stationary_draw"),
      "CAN-VELOCITY-OU":dict(velocity_rho=rho,velocity_noise_um=noise,initial_velocity="stationary_draw"),
      "CAN-SPEED-TURN":fit_speed_turn(steps,turns,a.speed_turn_variant),
      "CAN-SWITCH-PAUSE":fit_switch_pause(steps,alla),
      "CAN-SWITCH-TURN":fit_switch_turn(turns,alls),
      "CAN-SWITCH-SPEED":fit_switch_speed(steps,alla),
      "CAN-HET-SPEED":fit_het(steps,alla,a.heterogeneity_variant),
      "CAN-REVERSAL":fit_reversal(alls,alla),
      "CAN-EMP-LOCAL":dict(training_transition_table_uri=str(local.resolve()),training_transition_table_sha256=sha256(local),conditioning="iid_adjacent_pair"),
      "CAN-EMP-WHOLE":dict(training_trajectory_library_uri=str(whole.resolve()),training_trajectory_library_sha256=sha256(whole),orientation_policy=a.orientation_policy,post_sequence_policy=a.post_sequence_policy)
    }
    pfile=a.out/"canonical_parameters.toml"; write_toml(P,dt,pfile)
    summary=dict(source_xml=str(a.xml.resolve()),source_xml_sha256=sha256(a.xml),dt_sec=dt,n_tracks=len(tracks),n_positions=sum(len(t.frame) for t in tracks),n_steps=sum(len(x) for x in steps),n_turns=sum(len(x) for x in turns),speed_turn_variant=a.speed_turn_variant,heterogeneity_variant=a.heterogeneity_variant,models=P,artifacts=dict(parameters=str(pfile.resolve()),parameters_sha256=sha256(pfile),emp_local_sha256=sha256(local),emp_whole_sha256=sha256(whole)))
    (a.out/"fit_summary.json").write_text(json.dumps(summary,indent=2))
    print(f"Fitted 13 canonical classes from {len(tracks)} tracks")
    print(pfile)

if __name__=="__main__": main()
