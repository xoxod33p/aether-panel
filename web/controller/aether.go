package controller

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"aether-vpn/web/service"
)

type AetherController struct {
	BaseController

	inboundController *InboundController
	settingController *SettingController
	xrayService       service.XrayService
	serverService     service.ServerService
}

func NewAetherController(g *gin.RouterGroup) *AetherController {
	a := &AetherController{}
	a.initRouter(g)
	return a
}

func (a *AetherController) initRouter(g *gin.RouterGroup) {
	
	ag := g.Group("/aether")
	ag.Use(a.checkLogin)

	ag.GET("/", a.index)
	ag.GET("/inbounds", a.inbounds)
	ag.GET("/clients", a.clients)
	ag.GET("/logs", a.logs)
	ag.GET("/logs/data", a.getLogsData)
	ag.POST("/logs/clear", a.clearLogs)
	ag.GET("/setting", a.setting)

	a.inboundController = NewInboundController(ag)
	a.settingController = NewSettingController(ag)

	
	xg := g.Group("/xui")
	xg.Use(a.checkLogin)
	xg.GET("/", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/") })
	xg.GET("/inbounds", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/inbounds") })
	xg.GET("/clients", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/clients") })
	xg.GET("/logs", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/logs") })
	xg.GET("/setting", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/setting") })
	NewInboundController(xg)
	NewSettingController(xg)
}

func (a *AetherController) index(c *gin.Context) {
	html(c, "index.html", "System Status", nil)
}

func (a *AetherController) inbounds(c *gin.Context) {
	html(c, "inbounds.html", "Inbounds", nil)
}

func (a *AetherController) clients(c *gin.Context) {
	html(c, "clients.html", "Clients & QR Links", nil)
}

func (a *AetherController) logs(c *gin.Context) {
	html(c, "logs.html", "Live Logs", nil)
}

func (a *AetherController) getLogsData(c *gin.Context) {
	limitStr := c.DefaultQuery("limit", "250")
	limit, _ := strconv.Atoi(limitStr)
	if limit <= 0 || limit > 1000 {
		limit = 250
	}

	xrayLogs := a.xrayService.GetXrayLogs(limit)
	systemLogs := a.serverService.GetSystemLogs(limit)
	fileLogs := a.serverService.GetXrayFileLogs(limit)

	status := gin.H{
		"running":    a.xrayService.IsXrayRunning(),
		"version":    a.xrayService.GetXrayVersion(),
		"error":      a.xrayService.GetXrayResult(),
		"xrayLogs":   xrayLogs,
		"systemLogs": systemLogs,
		"fileLogs":   fileLogs,
		"serverTime": time.Now().Format("2006-01-02 15:04:05"),
	}
	jsonObj(c, status, nil)
}

func (a *AetherController) clearLogs(c *gin.Context) {
	a.xrayService.ClearXrayLogs()
	jsonMsg(c, "Logs cleared", nil)
}

func (a *AetherController) setting(c *gin.Context) {
	html(c, "setting.html", "Panel Settings", nil)
}
