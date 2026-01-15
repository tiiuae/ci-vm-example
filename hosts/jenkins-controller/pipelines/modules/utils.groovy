#!/usr/bin/env groovy

import groovy.json.JsonOutput

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout:true).trim()
}

def create_pipeline(List<Map> targets, String testagent_host = null) {
  def pipeline = [:]
  def stamp = run_cmd('date +"%Y%m%d_%H%M%S%3N"')
  def target_commit = run_cmd('git rev-parse HEAD')
  def artifacts = "artifacts/${env.JOB_BASE_NAME}/${stamp}-commit_${target_commit}"
  def artifacts_local_dir = "/var/lib/jenkins/${artifacts}"
  // Evaluate
  stage("Eval") {
    lock('evaluator') {
      sh 'nix flake show --all-systems | ansi2txt'
    }
  }
  targets.each {
    def shortname = it.target.substring(it.target.lastIndexOf('.') + 1)
    pipeline["${it.target}"] = {
      // Build
      stage("Build ${shortname}") {
        sh "nix build --fallback -v .#${it.target} --out-link ${artifacts_local_dir}/${it.target}"
      }
    }
  }
  return pipeline
}

return this
