import { hashCanonical } from './index.js';
import type { AppendBundle, CaseStateReceipt, DurableAppendResult, ReplayEnvelope } from './q-contract.js';

type TransitionDecision={allowed:boolean;reason?:string;transition_id?:string;missing_guards?:string[]};
type TransitionAuthorizer=(policy:unknown,from:string,to:string,eventType:string,satisfiedGuards:Set<string>)=>TransitionDecision;
type EligibilityEvaluator=(worker:any,context?:{aiRecommendation?:string})=>{worker_id:string;decision:string;predicate_results:Record<string,boolean>;decision_hash:string};
export interface QDurablePort{
  appendBundle(bundle:AppendBundle):Promise<DurableAppendResult>;
  caseState(correlationId:string):string|null|Promise<string|null>;
  caseStateReceipt?(correlationId:string):CaseStateReceipt|null|Promise<CaseStateReceipt|null>;
  replay(correlationId:string):unknown|Promise<unknown>;
  replayEnvelope?(correlationId:string):ReplayEnvelope|Promise<ReplayEnvelope>;
}
export type DurableTransitionCommand={from:string;to:string;satisfied_guards:string[];bundle:AppendBundle};
export class QKernelService{
  constructor(
    private readonly store:QDurablePort,
    private readonly transitionPolicy:unknown,
    private readonly domain:{authorizeTransition:TransitionAuthorizer;evaluateEligibility:EligibilityEvaluator}
  ){}
  async executeTransition(command:DurableTransitionCommand){
    const ev=command.bundle.event;
    const auth=this.domain.authorizeTransition(this.transitionPolicy,command.from,command.to,ev.event_type,new Set(command.satisfied_guards));
    if(!auth.allowed) throw new Error(`transition denied: ${auth.reason??'UNKNOWN'}${auth.missing_guards?.length?`:${auth.missing_guards.join(',')}`:''}`);
    const persisted=await this.store.caseState(ev.correlation_id);
    const expected=persisted??'REPORTED';
    if(command.from!==expected) throw new Error(`persisted state mismatch: expected ${expected} got ${command.from}`);
    if(ev.decision!==command.to) throw new Error(`event decision mismatch: expected ${command.to} got ${ev.decision??'null'}`);
    const base={correlation_id:ev.correlation_id,aggregate_id:ev.aggregate_id,aggregate_version:ev.aggregate_version,source_event_id:ev.event_id,state:command.to};
    const state={...base,state_hash:hashCanonical(base)};
    return this.store.appendBundle({...command.bundle,state});
  }
  evaluateWorker(worker:any,context?:{aiRecommendation?:string}){return this.domain.evaluateEligibility(worker,context);}
  caseState(correlationId:string){return this.store.caseState(correlationId);}
  caseStateReceipt(correlationId:string){return this.store.caseStateReceipt?.(correlationId)??null;}
  replay(correlationId:string){return this.store.replay(correlationId);}
  replayEnvelope(correlationId:string){return this.store.replayEnvelope?.(correlationId)??Promise.resolve(this.store.replay(correlationId)).then(replay=>({replay,certifications:[]}));}
}
