import type { GoldenEvent, ChainRecord } from './index.js';
import type { EvidenceRecord, StoreSnapshot } from './persistence.js';

export type VersionWrite={ref:string;record:unknown};
export type LineageWrite={id:string;parents:string[]};
export type CertificationWrite={certification_id:string;[key:string]:unknown};
export type CaseStateReceipt={
  correlation_id:string;
  aggregate_id:string;
  aggregate_version:number;
  source_event_id:string;
  state:string;
  state_hash:string;
};
export type AppendBundle={
  command_id:string;
  request_hash:string;
  event:GoldenEvent;
  evidence:EvidenceRecord[];
  versions:VersionWrite[];
  chain:ChainRecord[];
  lineage:LineageWrite[];
  certifications:CertificationWrite[];
  state?:CaseStateReceipt;
};
export type DurableAppendResult={status:'APPENDED'|'IDEMPOTENT_REPLAY';event_id:string};
export type DurableBackup={
  format:'CLP001-Q-BACKUP-v1';
  store:StoreSnapshot;
  command_request_hashes:Array<[string,string]>;
  state_history?:CaseStateReceipt[];
  certification_correlations?:Array<[string,string]>;
};
export type ReplayEnvelope={replay:any;certifications:CertificationWrite[]};
export interface DurableStore{
  appendBundle(bundle:AppendBundle):Promise<DurableAppendResult>;
  backup():DurableBackup;
  caseState?(correlationId:string):string|null|Promise<string|null>;
  caseStateReceipt?(correlationId:string):CaseStateReceipt|null|Promise<CaseStateReceipt|null>;
  replay?(correlationId:string):unknown|Promise<unknown>;
  replayEnvelope?(correlationId:string):ReplayEnvelope|Promise<ReplayEnvelope>;
}
export type SqlResult<T=Record<string,unknown>>={rows:T[];rowCount?:number|null};
export interface SqlClient{
  query<T=Record<string,unknown>>(sql:string,params?:unknown[]):Promise<SqlResult<T>>;
  release():void;
}
export interface SqlPool{ connect():Promise<SqlClient>; }
