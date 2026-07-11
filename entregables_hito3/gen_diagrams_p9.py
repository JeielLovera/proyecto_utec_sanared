# -*- coding: utf-8 -*-
"""
Alt. 3 Mejorada — Diagrama de componentes granular (punto 9) con iconos nativos
Genera PNG y SVG usando mingrammer 'diagrams' + Graphviz.
"""
import os

# Graphviz recien instalado por winget: asegurar que 'dot' este en PATH
GV_BIN = r"C:\Program Files\Graphviz\bin"
if os.path.isdir(GV_BIN):
    os.environ["PATH"] = GV_BIN + os.pathsep + os.environ.get("PATH", "")

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Fargate, ECR, EC2
from diagrams.aws.network import APIGateway, ElasticLoadBalancing, Endpoint, Privatelink, VPC
from diagrams.aws.database import RDSPostgresqlInstance, ElasticacheForRedis
from diagrams.aws.analytics import AmazonOpensearchService, ManagedStreamingForKafka
from diagrams.aws.security import WAF, Cognito, IAM, KMS, SecretsManager
from diagrams.aws.management import Cloudwatch, SystemsManagerParameterStore

from diagrams.azure.compute import FunctionApps
from diagrams.azure.integration import APIManagement
from diagrams.azure.security import KeyVaults
from diagrams.azure.identity import ManagedIdentities
from diagrams.azure.network import VirtualNetworks, PrivateEndpoint, ExpressrouteCircuits
from diagrams.azure.database import SQLManagedInstances

from diagrams.gcp.compute import Run
from diagrams.gcp.analytics import BigQuery
from diagrams.gcp.storage import Storage
from diagrams.gcp.security import Iam as GIam, SecretManager
from diagrams.gcp.network import PrivateServiceConnect, VirtualPrivateCloud
from diagrams.gcp.api import Endpoints

from diagrams.onprem.client import User
from diagrams.onprem.database import Oracle
from diagrams.generic.blank import Blank

OUT = r"c:\Users\Jeiel\Personales\UTEC\Modulo 9\proyecto_utec\entregables_hito3\Alt3M_Flujos_Componentes_Cloud"

graph_attr = {
    "fontsize": "22", "fontname": "Segoe UI", "bgcolor": "white",
    "pad": "0.6", "nodesep": "0.55", "ranksep": "1.1",
    "splines": "spline", "compound": "true",
}
node_attr = {"fontsize": "11", "fontname": "Segoe UI"}
edge_attr = {"fontsize": "10", "fontname": "Segoe UI"}

# Colores para aristas
X = "#b71c1c"      # interconexion cross-cloud (rojo, grueso)
DASH = "#607d8b"   # soporte transversal (punteado gris)


def build(fmt):
    with Diagram(
        "Alt. 3 Mejorada — Piezas cloud de los flujos de registro (EMPI)",
        filename=OUT, outformat=fmt, show=False, direction="LR",
        graph_attr=graph_attr, node_attr=node_attr, edge_attr=edge_attr,
    ):
        # ---------- Actores ----------
        with Cluster("Actores / Canales", graph_attr={"bgcolor": "#eceff1", "style": "rounded"}):
            pac = User("Paciente")
            adm = User("Admisionista")
            opd = User("Operador\nGobierno de Datos")

        # ---------- AWS ----------
        with Cluster("AWS — Dominio del PACIENTE + Bus de eventos",
                     graph_attr={"bgcolor": "#e3f2fd", "style": "rounded"}):
            cog = Cognito("Amazon Cognito\nauth paciente (JWT)")
            portal = EC2("Portal de Pacientes\n(existente)")
            waf = WAF("AWS WAF")
            apigw = APIGateway("Amazon API Gateway\n(canales públicos · WAF)")
            apimtls = APIGateway("API Gateway privado / ALB\nmTLS interno")
            vpcl = Endpoint("API Gateway VPC Link")
            elb = ElasticLoadBalancing("ELB (NLB/ALB)")
            ecr = ECR("Amazon ECR\nimagen EMPI Core")
            core = Fargate("ECS Fargate\nEMPI Core + Matcher RT")
            redis = ElasticacheForRedis("ElastiCache Redis\nPaso 1 · lookup DNI")
            osx = AmazonOpensearchService("OpenSearch\nPaso 2 · blocking")
            rds = RDSPostgresqlInstance("RDS PostgreSQL\nevents · golden_record\naudit · review_queue")
            sm = SecretsManager("Secrets Manager")
            ssm = SystemsManagerParameterStore("Parameter Store\numbrales 0.95/0.85")
            kafka = ManagedStreamingForKafka("Kafka en AWS\nConfluent(región AWS)/MSK\nidentity.patient.* · DLQ")
            plink = Privatelink("AWS PrivateLink\nVPC Endpoints")
            with Cluster("Capa transversal AWS",
                         graph_attr={"bgcolor": "#bbdefb", "style": "rounded"}):
                vpc = VPC("Amazon VPC\nsubnets · SG")
                iam = IAM("AWS IAM\nroles de servicio")
                kms = KMS("AWS KMS\ncifrado en reposo")
                cw = Cloudwatch("CloudWatch\n+ X-Ray")

        # ---------- Azure ----------
        with Cluster("Azure — Integración CLÍNICA y FINANCIERA",
                     graph_attr={"bgcolor": "#e8eaf6", "style": "rounded"}):
            azpl = PrivateEndpoint("Azure Private Link")
            apim = APIManagement("Azure API Management\nmTLS interno")
            fcli = FunctionApps("Azure Functions\nAdaptador Clínico\nHL7v2 ADT^A28/A40")
            ffin = FunctionApps("Azure Functions\nAdaptador Financiero")
            lis = SQLManagedInstances("Azure SQL MI · LIS\n(existente)")
            pagos = Blank("Portal de Pagos\n(existente)")
            xr = ExpressrouteCircuits("ExpressRoute / VPN")
            with Cluster("Capa transversal Azure",
                         graph_attr={"bgcolor": "#c5cae9", "style": "rounded"}):
                avnet = VirtualNetworks("Azure VNet\nsubnets · NSG")
                mi = ManagedIdentities("Managed Identity")
                kv = KeyVaults("Key Vault\ncred. Kafka / certs")

        # ---------- GCP ----------
        with Cluster("GCP — IMÁGENES y ANALÍTICA",
                     graph_attr={"bgcolor": "#e8f5e9", "style": "rounded"}):
            psc = PrivateServiceConnect("Private Service Connect")
            grun = Run("Cloud Run / Functions\nConsumidor Kafka")
            fhir = Endpoints("Cloud Healthcare API\nFHIR Store")
            dicom = Endpoints("Cloud Healthcare API\nDICOM Store")
            gcs = Storage("Cloud Storage\nPACS réplica")
            bq = BigQuery("BigQuery\nVista 360°")
            with Cluster("Capa transversal GCP",
                         graph_attr={"bgcolor": "#c8e6c9", "style": "rounded"}):
                gvpc = VirtualPrivateCloud("VPC + firewall")
                giam = GIam("Cloud IAM\nService Accounts")
                gsm = SecretManager("Secret Manager\ncred. Kafka")

        # ---------- On-prem / privada ----------
        with Cluster("On-premises Lima", graph_attr={"bgcolor": "#f3e5f5", "style": "rounded"}):
            admis = Blank("Módulo de Admisión local\n(por sede · sobre HCE)")
            hce = Oracle("HCE Oracle\nHL7 v2")
            pacsl = Blank("PACS local\npor sede")

        with Cluster("Nube privada", graph_attr={"bgcolor": "#fce4ec", "style": "rounded"}):
            erp = Blank("ERP Facturación")

        # ===== Camino caliente del alta — canal PACIENTE (publico, WAF) =====
        pac >> portal >> waf >> apigw
        portal >> Edge(label="login") >> cog
        cog >> Edge(label="valida JWT", style="dashed", color=DASH) >> apigw
        apigw >> vpcl >> elb >> core

        # ===== Canal ADMISIONISTA (interno, mTLS, sin WAF, sin Azure) =====
        adm >> admis
        admis >> Edge(label="mTLS · Direct Connect/VPN", color=X, penwidth="2.5") >> apimtls
        apimtls >> core
        admis >> Edge(label="opera sobre HCE", style="dashed", color=DASH) >> hce
        ecr >> Edge(label="imagen", style="dashed", color=DASH) >> core
        core >> Edge(label="1) lookup/cache DNI") >> redis
        core >> Edge(label="2) blocking + index") >> osx
        core >> Edge(label="append eventos · proyecta") >> rds
        core >> Edge(label="creds", style="dashed", color=DASH) >> sm
        core >> Edge(label="umbrales", style="dashed", color=DASH) >> ssm
        opd >> Edge(label="resuelve cola B3") >> rds
        core >> Edge(label="publica created/merged") >> kafka

        # ===== Plataforma transversal AWS =====
        iam >> Edge(style="dashed", color=DASH) >> core
        kms >> Edge(style="dashed", color=DASH) >> rds
        cw >> Edge(style="dashed", color=DASH) >> core
        vpc >> Edge(style="dashed", color=DASH) >> core

        # ===== Interconexion privada cross-cloud =====
        kafka >> Edge(color=X, penwidth="2.5") >> plink
        plink >> Edge(label="Azure Private Link · async", color=X, penwidth="2.5") >> azpl
        plink >> Edge(label="Private Service Connect · async", color=X, penwidth="2.5") >> psc
        azpl >> fcli
        azpl >> ffin
        psc >> grun

        # ===== Azure - integracion =====
        fcli >> apim
        fcli >> Edge(label="certs", style="dashed", color=DASH) >> kv
        fcli >> Edge(style="dashed", color=DASH) >> mi
        avnet >> Edge(style="dashed", color=DASH) >> fcli
        apim >> Edge(label="ADT^A28/A40 · mTLS", color=X, penwidth="2.5") >> xr
        xr >> Edge(color=X, penwidth="2.5") >> hce
        fcli >> Edge(label="vincula resultados · EMPI-ID") >> lis
        ffin >> Edge(label="EMPI-ID activo") >> erp
        ffin >> Edge(label="consolida cuentas") >> pagos

        # ===== GCP - consumidor + imagenes/360 =====
        grun >> Edge(label="escribe FHIR / tag DICOM") >> fhir
        giam >> Edge(style="dashed", color=DASH) >> grun
        gsm >> Edge(label="cred. Kafka", style="dashed", color=DASH) >> grun
        gvpc >> Edge(style="dashed", color=DASH) >> grun
        fhir >> dicom
        dicom >> Edge(label="etiqueta/re-etiqueta EMPI-ID") >> gcs
        dicom >> Edge(label="EMPI-ID en tags DICOM", style="dashed", color=DASH) >> pacsl
        fhir >> bq
        rds >> Edge(label="datos de identidad", style="dashed", color=DASH) >> bq


if __name__ == "__main__":
    for fmt in ("png", "svg"):
        build(fmt)
        print("OK ->", OUT + "." + fmt)
